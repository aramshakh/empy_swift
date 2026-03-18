//
//  TranscriptEngine.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Manages transcript accumulation and state from Deepgram
//

import Foundation
import Combine

/// Manages transcript accumulation and state.
///
/// Bubble lifecycle:
///   partial   → update open bubble in real-time (isFinal: false)
///   isFinal   → update open bubble with confirmed text (isFinal: true), keep open
///   speechFinal → same as isFinal, keep open
///   UtteranceEnd → SEAL bubble (1200ms silence = end of sentence)
///   20s timer → force-seal if speech runs non-stop for 20s
class TranscriptEngine: ObservableObject {
    /// Current transcript state (observable for UI)
    @Published private(set) var transcriptState = TranscriptState()
    
    /// Deepgram client for receiving transcripts
    private let deepgramClient: DeepgramClient
    
    /// Session logger
    private let logger: SessionLogger
    
    // MARK: - Active bubble state
    
    /// The currently open bubble (growing in real-time)
    private var activeBubble: TranscriptSegment?
    
    /// Speaker of the current bubble
    private var activeBubbleSpeaker: String?
    
    /// When the current bubble was first opened (for 20s forced seal)
    private var bubbleStartTime: Date?
    
    /// Timer that force-seals the bubble after 20s of continuous speech
    private var sealTimer: Timer?
    
    /// Max duration before forcing a new bubble (even mid-speech)
    private let maxBubbleDuration: TimeInterval = 20.0
    
    init(
        deepgramClient: DeepgramClient,
        logger: SessionLogger = .shared
    ) {
        self.deepgramClient = deepgramClient
        self.logger = logger
        self.deepgramClient.delegate = self
    }
    
    // MARK: - Public API
    
    func startSession() throws {
        clearState()
        do {
            try deepgramClient.connect()
            logger.log(event: "transcription_session_started", layer: "transcript")
        } catch {
            logger.log(event: "transcription_session_failed", layer: "transcript",
                       details: ["error": error.localizedDescription])
            throw error
        }
    }
    
    func endSession() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run { sealActiveBubble() }
        deepgramClient.disconnect()
        logger.log(event: "transcription_session_ended", layer: "transcript",
                   details: ["final_word_count": "\(transcriptState.wordCount)",
                             "segment_count": "\(transcriptState.finalCount)"])
    }
    
    func clearState() {
        transcriptState = TranscriptState()
        activeBubble = nil
        activeBubbleSpeaker = nil
        bubbleStartTime = nil
        sealTimer?.invalidate()
        sealTimer = nil
        logger.log(event: "transcript_state_cleared", layer: "transcript")
    }
    
    func processAudioChunk(_ audioData: Data) {
        deepgramClient.send(audioData: audioData)
    }
    
    // MARK: - Bubble management (main thread only)
    
    /// Update the active bubble text in-place, or open a new one.
    private func updateActiveBubble(text: String, speaker: String?, isFinal: Bool) {
        if let existing = activeBubble {
            let updated = TranscriptSegment(
                updating: existing,
                text: text,
                confidence: isFinal ? 1.0 : 0.0,
                isFinal: isFinal
            )
            if let idx = transcriptState.segments.firstIndex(where: { $0.id == existing.id }) {
                transcriptState.segments[idx] = updated
            } else {
                transcriptState.segments.append(updated)
            }
            activeBubble = updated
        } else {
            let newBubble = TranscriptSegment(
                text: text,
                speaker: speaker,
                confidence: isFinal ? 1.0 : 0.0,
                isFinal: isFinal
            )
            activeBubble = newBubble
            activeBubbleSpeaker = speaker
            bubbleStartTime = Date()
            transcriptState.segments.append(newBubble)
            
            // Force-seal after maxBubbleDuration even if UtteranceEnd never fires
            sealTimer?.invalidate()
            sealTimer = Timer.scheduledTimer(
                withTimeInterval: maxBubbleDuration,
                repeats: false
            ) { [weak self] _ in
                self?.sealActiveBubble()
            }
        }
    }
    
    /// Seal the active bubble: mark final, clear active state.
    /// Next speech will open a fresh bubble below.
    private func sealActiveBubble() {
        guard let existing = activeBubble else { return }
        
        let sealed = TranscriptSegment(
            updating: existing,
            text: existing.text,
            confidence: 1.0,
            isFinal: true
        )
        if let idx = transcriptState.segments.firstIndex(where: { $0.id == existing.id }) {
            transcriptState.segments[idx] = sealed
        }
        
        activeBubble = nil
        activeBubbleSpeaker = nil
        bubbleStartTime = nil
        sealTimer?.invalidate()
        sealTimer = nil
        
        logger.log(event: "transcript_bubble_sealed", layer: "transcript",
                   details: ["text_preview": String(sealed.text.prefix(50))])
    }
}

// MARK: - DeepgramClientDelegate

extension TranscriptEngine: DeepgramClientDelegate {
    
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript transcript: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Real-time preview — bubble stays open, text grows
            self.updateActiveBubble(text: transcript, speaker: self.activeBubbleSpeaker, isFinal: false)
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String) {
        guard !transcript.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Confirmed chunk — update bubble, keep open until UtteranceEnd
            self.updateActiveBubble(text: transcript, speaker: self.activeBubbleSpeaker, isFinal: true)
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveSpeechFinal transcript: String) {
        guard !transcript.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Last confirmed chunk before pause — update, keep open until UtteranceEnd
            self.updateActiveBubble(text: transcript, speaker: self.activeBubbleSpeaker, isFinal: true)
        }
    }
    
    func deepgramClientDidReceiveUtteranceEnd(_ client: DeepgramClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 1200ms of silence = end of sentence → seal, next speech = new bubble
            self.sealActiveBubble()
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didEncounterError error: Error) {
        logger.log(event: "transcript_error", layer: "transcript",
                   details: ["error": error.localizedDescription])
    }
    
    func deepgramClientDidConnect(_ client: DeepgramClient) {
        logger.log(event: "transcript_connected", layer: "transcript")
    }
    
    func deepgramClientDidDisconnect(_ client: DeepgramClient) {
        logger.log(event: "transcript_disconnected", layer: "transcript")
    }
}
