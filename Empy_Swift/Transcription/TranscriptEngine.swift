//
//  TranscriptEngine.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Manages transcript accumulation and state from Deepgram
//
//  T04: Dual-stream support — mic = .you, system audio = .participant
//

import Foundation
import Combine

/// Manages transcript accumulation from two independent Deepgram streams.
///
/// Each stream (mic / system audio) has its own open bubble and confirmedText
/// so they never overwrite each other. Bubbles are keyed by speaker label.
///
/// Bubble lifecycle per sentence (per speaker):
///   partial      → display: confirmedText + " " + partialText  (isFinal: false)
///   isFinal      → confirmedText += chunk; display confirmedText; keep open
///   speechFinal  → same as isFinal
///   UtteranceEnd → seal bubble (1200ms silence = sentence boundary)
///   20s timer    → force-seal for non-stop speech
class TranscriptEngine: ObservableObject {
    @Published private(set) var transcriptState = TranscriptState()

    let micClient: DeepgramClient
    let systemClient: DeepgramClient
    fileprivate let logger: SessionLogger

    // Strong references to delegate wrappers — DeepgramClient.delegate is weak
    private var micDelegate: MicDelegate?
    private var systemDelegate: SystemDelegate?

    // MARK: - Per-speaker bubble state (main thread only)

    /// Open bubble per speaker label ("you" / "Other")
    private var activeBubbles:  [String: TranscriptSegment] = [:]
    /// Accumulated confirmed text per speaker
    private var confirmedTexts: [String: String]            = [:]
    /// 20s force-seal timer per speaker
    private var sealTimers:     [String: Timer]             = [:]
    private let maxBubbleDuration: TimeInterval = 20.0

    // MARK: - Init

    init(micClient: DeepgramClient, systemClient: DeepgramClient, logger: SessionLogger = .shared) {
        self.micClient    = micClient
        self.systemClient = systemClient
        self.logger       = logger
        let md = MicDelegate(engine: self)
        let sd = SystemDelegate(engine: self)
        self.micDelegate    = md
        self.systemDelegate = sd
        micClient.delegate    = md
        systemClient.delegate = sd
    }

    /// Convenience init for single-stream / backwards compat
    convenience init(deepgramClient: DeepgramClient, logger: SessionLogger = .shared) {
        self.init(micClient: deepgramClient, systemClient: deepgramClient, logger: logger)
    }

    // MARK: - Public API

    func startSession() throws {
        clearState()
        do {
            try micClient.connect()
            // systemClient connects only after mic is running (called separately)
            logger.log(event: "transcription_session_started", layer: "transcript")
        } catch {
            logger.log(event: "transcription_session_failed", layer: "transcript",
                       details: ["error": error.localizedDescription])
            throw error
        }
    }

    func startSystemStream() throws {
        guard systemClient !== micClient else { return }
        try systemClient.connect()
        logger.log(event: "system_stream_started", layer: "transcript")
    }

    func endSession() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            sealAll()
        }
        micClient.disconnect()
        if systemClient !== micClient { systemClient.disconnect() }
        logger.log(event: "transcription_session_ended", layer: "transcript",
                   details: ["final_word_count": "\(transcriptState.wordCount)",
                             "segment_count":    "\(transcriptState.finalCount)"])
    }

    func clearState() {
        transcriptState = TranscriptState()
        activeBubbles.removeAll()
        confirmedTexts.removeAll()
        sealTimers.values.forEach { $0.invalidate() }
        sealTimers.removeAll()
        logger.log(event: "transcript_state_cleared", layer: "transcript")
    }

    // MARK: - Bubble management (main thread only)

    func applyPartial(_ text: String, speaker: String) {
        let confirmed = confirmedTexts[speaker] ?? ""
        let display   = confirmed.isEmpty ? text : confirmed + " " + text
        writeToBubble(text: display, isFinal: false, speaker: speaker)
    }

    func applyFinal(_ text: String, speaker: String) {
        let confirmed = confirmedTexts[speaker] ?? ""
        confirmedTexts[speaker] = confirmed.isEmpty ? text : confirmed + " " + text
        writeToBubble(text: confirmedTexts[speaker]!, isFinal: true, speaker: speaker)
    }

    func sealBubble(for speaker: String) {
        guard let existing = activeBubbles[speaker] else { return }

        let sealed = TranscriptSegment(
            updating: existing,
            text: existing.text,
            confidence: 1.0,
            isFinal: true
        )
        if let idx = transcriptState.segments.firstIndex(where: { $0.id == existing.id }) {
            transcriptState.segments[idx] = sealed
        }

        activeBubbles.removeValue(forKey: speaker)
        confirmedTexts.removeValue(forKey: speaker)
        sealTimers[speaker]?.invalidate()
        sealTimers.removeValue(forKey: speaker)

        logger.log(event: "transcript_bubble_sealed", layer: "transcript",
                   details: ["speaker": speaker,
                             "text_preview": String(sealed.text.prefix(60))])
    }

    private func sealAll() {
        for speaker in activeBubbles.keys {
            sealBubble(for: speaker)
        }
    }

    private func writeToBubble(text: String, isFinal: Bool, speaker: String) {
        if let existing = activeBubbles[speaker] {
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
            activeBubbles[speaker] = updated
        } else {
            let newBubble = TranscriptSegment(
                text: text,
                speaker: speaker,
                confidence: isFinal ? 1.0 : 0.0,
                isFinal: isFinal
            )
            activeBubbles[speaker] = newBubble
            transcriptState.segments.append(newBubble)

            sealTimers[speaker]?.invalidate()
            sealTimers[speaker] = Timer.scheduledTimer(
                withTimeInterval: maxBubbleDuration,
                repeats: false
            ) { [weak self] _ in
                self?.sealBubble(for: speaker)
            }
        }
    }
}

// MARK: - Private delegate wrappers
// Each wrapper tags incoming events with the correct speaker label.

private class MicDelegate: DeepgramClientDelegate {
    weak var engine: TranscriptEngine?
    init(engine: TranscriptEngine) { self.engine = engine }

    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript t: String) {
        DispatchQueue.main.async { self.engine?.applyPartial(t, speaker: "you") }
    }
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript t: String) {
        guard !t.isEmpty else { return }
        DispatchQueue.main.async { self.engine?.applyFinal(t, speaker: "you") }
    }
    func deepgramClient(_ client: DeepgramClient, didReceiveSpeechFinal t: String) {
        guard !t.isEmpty else { return }
        DispatchQueue.main.async { self.engine?.applyFinal(t, speaker: "you") }
    }
    func deepgramClientDidReceiveUtteranceEnd(_ client: DeepgramClient) {
        DispatchQueue.main.async { self.engine?.sealBubble(for: "you") }
    }
    func deepgramClient(_ client: DeepgramClient, didEncounterError error: Error) {
        self.engine?.logger.log(event: "mic_transcript_error", layer: "transcript",
                                details: ["error": error.localizedDescription])
    }
    func deepgramClientDidConnect(_ client: DeepgramClient) {
        self.engine?.logger.log(event: "mic_stream_connected", layer: "transcript")
    }
    func deepgramClientDidDisconnect(_ client: DeepgramClient) {
        self.engine?.logger.log(event: "mic_stream_disconnected", layer: "transcript")
    }
}

private class SystemDelegate: DeepgramClientDelegate {
    weak var engine: TranscriptEngine?
    init(engine: TranscriptEngine) { self.engine = engine }

    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript t: String) {
        DispatchQueue.main.async { self.engine?.applyPartial(t, speaker: "Other") }
    }
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript t: String) {
        guard !t.isEmpty else { return }
        DispatchQueue.main.async { self.engine?.applyFinal(t, speaker: "Other") }
    }
    func deepgramClient(_ client: DeepgramClient, didReceiveSpeechFinal t: String) {
        guard !t.isEmpty else { return }
        DispatchQueue.main.async { self.engine?.applyFinal(t, speaker: "Other") }
    }
    func deepgramClientDidReceiveUtteranceEnd(_ client: DeepgramClient) {
        DispatchQueue.main.async { self.engine?.sealBubble(for: "Other") }
    }
    func deepgramClient(_ client: DeepgramClient, didEncounterError error: Error) {
        self.engine?.logger.log(event: "system_transcript_error", layer: "transcript",
                                details: ["error": error.localizedDescription])
    }
    func deepgramClientDidConnect(_ client: DeepgramClient) {
        self.engine?.logger.log(event: "system_stream_connected", layer: "transcript")
        print("🔊 System audio Deepgram connected")
    }
    func deepgramClientDidDisconnect(_ client: DeepgramClient) {
        self.engine?.logger.log(event: "system_stream_disconnected", layer: "transcript")
    }
}
