//
//  TranscriptEngine.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Manages transcript accumulation and state from Deepgram
//

import Foundation
import Combine

/// Manages transcript accumulation and state
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
    
    /// Timer that seals the bubble after 20s of continuous speech
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
    
    /// Start transcription session
    func startSession() throws {
        clearState()

        do {
            try deepgramClient.connect()
            logger.log(event: "transcription_session_started", layer: "transcript")
        } catch {
            logger.log(
                event: "transcription_session_failed",
                layer: "transcript",
                details: ["error": error.localizedDescription]
            )
            throw error
        }
    }
    
    /// End transcription session
    func endSession() async {
        // Give Deepgram time to send final transcripts before disconnecting
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        await MainActor.run {
            // Seal any open bubble as final
            sealActiveBubble()
        }
        
        deepgramClient.disconnect()
        logger.log(
            event: "transcription_session_ended",
            layer: "transcript",
            details: [
                "final_word_count": "\(transcriptState.wordCount)",
                "segment_count": "\(transcriptState.finalCount)"
            ]
        )
    }
    
    /// Clear all transcript state
    func clearState() {
        transcriptState = TranscriptState()
        activeBubble = nil
        activeBubbleSpeaker = nil
        bubbleStartTime = nil
        sealTimer?.invalidate()
        sealTimer = nil
        
        logger.log(event: "transcript_state_cleared", layer: "transcript")
    }
    
    /// Send audio chunk to Deepgram
    func processAudioChunk(_ audioData: Data) {
        deepgramClient.send(audioData: audioData)
    }
    
    // MARK: - Bubble management (always called on main thread)
    
    /// Update the active bubble's text in-place, or open a new one.
    /// isFinal=false → partial (live preview); isFinal=true → confirmed text.
    private func updateActiveBubble(text: String, speaker: String?, isFinal: Bool) {
        if let existing = activeBubble {
            // Update in-place — same UUID, so ForEach doesn't re-create the row
            let updated = TranscriptSegment(updating: existing, text: text, confidence: isFinal ? 1.0 : 0.0, isFinal: isFinal)
            if let idx = transcriptState.segments.firstIndex(where: { $0.id == existing.id }) {
                transcriptState.segments[idx] = updated
            } else {
                transcriptState.segments.append(updated)
            }
            activeBubble = updated
        } else {
            // Open a new bubble
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
            
            // Start 20s forced-seal timer on main thread
            sealTimer?.invalidate()
            sealTimer = Timer.scheduledTimer(withTimeInterval: maxBubbleDuration, repeats: false) { [weak self] _ in
                self?.sealActiveBubble()
            }
        }
    }
    
    /// Permanently seal the active bubble (mark isFinal=true, clear active state).
    /// After this, the next speech opens a fresh bubble below.
    private func sealActiveBubble() {
        guard let existing = activeBubble else { return }
        
        let sealed = TranscriptSegment(updating: existing, text: existing.text, confidence: 1.0, isFinal: true)
        if let idx = transcriptState.segments.firstIndex(where: { $0.id == existing.id }) {
            transcriptState.segments[idx] = sealed
        }
        
        activeBubble = nil
        activeBubbleSpeaker = nil
        bubbleStartTime = nil
        sealTimer?.invalidate()
        sealTimer = nil
        
        logger.log(
            event: "transcript_bubble_sealed",
            layer: "transcript",
            details: ["text_preview": String(sealed.text.prefix(50))]
        )
    }
}

// MARK: - DeepgramClientDelegate

extension TranscriptEngine: DeepgramClientDelegate {
    
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript transcript: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Live preview: update current bubble with partial text (isFinal: false)
            self.updateActiveBubble(text: transcript, speaker: self.activeBubbleSpeaker, isFinal: false)
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String) {
        guard !transcript.isEmpty else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Confirmed text for current bubble
            self.updateActiveBubble(text: transcript, speaker: self.activeBubbleSpeaker, isFinal: true)
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveSpeechFinal transcript: String) {
        guard !transcript.isEmpty else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // speechFinal = speaker paused → update bubble with final text, then seal it
            self.updateActiveBubble(text: transcript, speaker: self.activeBubbleSpeaker, isFinal: true)
            self.sealActiveBubble()
            
            self.logger.log(
                event: "transcript_speech_final",
                layer: "transcript",
                details: ["text": String(transcript.prefix(50))]
            )
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didEncounterError error: Error) {
        logger.log(
            event: "transcript_error",
            layer: "transcript",
            details: ["error": error.localizedDescription]
        )
    }
    
    func deepgramClientDidConnect(_ client: DeepgramClient) {
        logger.log(event: "transcript_connected", layer: "transcript")
    }
    
    func deepgramClientDidDisconnect(_ client: DeepgramClient) {
        logger.log(event: "transcript_disconnected", layer: "transcript")
    }
}
