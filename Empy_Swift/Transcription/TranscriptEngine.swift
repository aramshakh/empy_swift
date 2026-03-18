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
/// Key insight: Deepgram partials are NOT cumulative — each partial is only
/// the current in-progress fragment, not the full sentence. We must separately
/// track confirmedText (from isFinal chunks) and append the current partial
/// on top of it for display.
///
/// Bubble lifecycle per sentence:
///   partial       → display: confirmedText + " " + partialText  (isFinal: false)
///   isFinal       → confirmedText += chunk; display confirmedText (isFinal: true); keep open
///   speechFinal   → same as isFinal
///   UtteranceEnd  → seal bubble (1200ms silence = sentence boundary)
///   20s timer     → force-seal for non-stop speech
class TranscriptEngine: ObservableObject {
    @Published private(set) var transcriptState = TranscriptState()
    
    private let deepgramClient: DeepgramClient
    private let logger: SessionLogger
    
    // MARK: - Active bubble state (main thread only)
    
    /// The segment currently displayed as the open bubble
    private var activeBubble: TranscriptSegment?
    
    /// Accumulated confirmed text for the current bubble (from isFinal chunks)
    private var confirmedText: String = ""
    
    private var activeBubbleSpeaker: String?
    private var bubbleStartTime: Date?
    private var sealTimer: Timer?
    private let maxBubbleDuration: TimeInterval = 20.0
    
    init(deepgramClient: DeepgramClient, logger: SessionLogger = .shared) {
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
        confirmedText = ""
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
    
    /// Show partial: confirmed text so far + current in-progress fragment.
    /// This never advances confirmedText — only updates the display.
    private func applyPartial(_ partialText: String) {
        let displayText = confirmedText.isEmpty
            ? partialText
            : confirmedText + " " + partialText
        writeToBubble(text: displayText, isFinal: false)
    }
    
    /// Advance confirmedText with a new isFinal chunk, update bubble display.
    private func applyFinal(_ finalText: String) {
        confirmedText = confirmedText.isEmpty
            ? finalText
            : confirmedText + " " + finalText
        writeToBubble(text: confirmedText, isFinal: true)
    }
    
    /// Write text into the active bubble (in-place update) or open a new one.
    private func writeToBubble(text: String, isFinal: Bool) {
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
                speaker: activeBubbleSpeaker,
                confidence: isFinal ? 1.0 : 0.0,
                isFinal: isFinal
            )
            activeBubble = newBubble
            bubbleStartTime = Date()
            transcriptState.segments.append(newBubble)
            
            sealTimer?.invalidate()
            sealTimer = Timer.scheduledTimer(withTimeInterval: maxBubbleDuration, repeats: false) { [weak self] _ in
                self?.sealActiveBubble()
            }
        }
    }
    
    /// Seal the bubble: mark isFinal=true, reset confirmed text, clear active state.
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
        confirmedText = ""          // ← reset for next sentence
        activeBubbleSpeaker = nil
        bubbleStartTime = nil
        sealTimer?.invalidate()
        sealTimer = nil
        
        logger.log(event: "transcript_bubble_sealed", layer: "transcript",
                   details: ["text_preview": String(sealed.text.prefix(60))])
    }
}

// MARK: - DeepgramClientDelegate

extension TranscriptEngine: DeepgramClientDelegate {
    
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript transcript: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyPartial(transcript)
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript transcript: String) {
        guard !transcript.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyFinal(transcript)
        }
    }
    
    func deepgramClient(_ client: DeepgramClient, didReceiveSpeechFinal transcript: String) {
        guard !transcript.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyFinal(transcript)
        }
    }
    
    func deepgramClientDidReceiveUtteranceEnd(_ client: DeepgramClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
