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

    /// Open bubble per speaker label ("you" / "Speaker 0" etc.)
    var activeBubbles:  [String: TranscriptSegment] = [:]
    /// Accumulated confirmed text per speaker
    private var confirmedTexts: [String: String]            = [:]
    /// 20s force-seal timer per speaker (max bubble duration)
    private var sealTimers:     [String: Timer]             = [:]
    private let maxBubbleDuration: TimeInterval = 20.0

    /// Debounce timers: seal only fires after 2s silence per speaker.
    /// Restarted every time new text arrives — prevents single-word bubbles.
    private var sealDebounceTimers: [String: Timer] = [:]
    private let sealDebounceInterval: TimeInterval = 2.0

    /// Minimum words a bubble must have before a speaker-switch creates a new bubble.
    /// Prevents 1-2 word orphan bubbles from diarization noise.
    private let minWordsBeforeSplit = 4

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

        // System stream uses Deepgram diarization to separate speakers in the video/call.
        // Speaker IDs from Deepgram (0, 1, 2…) map to stable display labels.
        // The mic stream has no resolver — it always goes to "you" via MicDelegate.
        systemClient.useDiarization = true
        // No maxSpeakers limit — calls can have 3-4+ participants and each should
        // get their own bubble. Speaker IDs from Deepgram are stable within a session.
        systemClient.speakerResolver = { speakerId in
            guard let id = speakerId else { return "Other" }
            return "Speaker \(id)"
        }
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
        sealDebounceTimers.values.forEach { $0.invalidate() }
        sealDebounceTimers.removeAll()
        logger.log(event: "transcript_state_cleared", layer: "transcript")
    }

    // MARK: - Bubble management (main thread only)

    func applyPartial(_ text: String, speaker: String) {
        let confirmed = confirmedTexts[speaker] ?? ""
        let display   = confirmed.isEmpty ? text : confirmed + " " + text
        writeToBubble(text: display, isFinal: false, speaker: speaker)
    }

    func applyFinal(_ text: String, speaker: String) {
        // Speaker-switch: seal the other speaker's bubble only if it has enough words.
        // Short bubbles (< minWordsBeforeSplit words) get merged into the current speaker
        // instead — prevents orphan 1-2 word bubbles from diarization noise.
        if speaker != "you" {
            for openSpeaker in activeBubbles.keys where openSpeaker != speaker && openSpeaker != "you" {
                let wordCount = (confirmedTexts[openSpeaker] ?? "").split(separator: " ").count
                if wordCount >= minWordsBeforeSplit {
                    sealBubble(for: openSpeaker)
                }
                // else: too short — leave open, next isFinal will overwrite or extend it
            }
        }

        let confirmed = confirmedTexts[speaker] ?? ""
        confirmedTexts[speaker] = confirmed.isEmpty ? text : confirmed + " " + text
        writeToBubble(text: confirmedTexts[speaker]!, isFinal: true, speaker: speaker)

        // Restart the debounce seal timer — if no more text arrives in 2s, seal the bubble.
        // This replaces the "seal on UtteranceEnd" path for short utterances.
        scheduleSealDebounce(for: speaker)
    }

    /// Schedule a debounced seal: fires 2s after the last text chunk.
    /// Cancelled and restarted on every new applyFinal call for this speaker.
    func scheduleSealDebounce(for speaker: String) {
        sealDebounceTimers[speaker]?.invalidate()
        sealDebounceTimers[speaker] = Timer.scheduledTimer(
            withTimeInterval: sealDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.sealBubble(for: speaker)
        }
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
        sealDebounceTimers[speaker]?.invalidate()
        sealDebounceTimers.removeValue(forKey: speaker)

        logger.log(event: "transcript_bubble_sealed", layer: "transcript",
                   details: ["speaker": speaker,
                             "text_preview": String(sealed.text.prefix(60))])
    }

    private func sealAll() {
        for speaker in activeBubbles.keys {
            sealBubble(for: speaker)
        }
    }

    /// Seal all open bubbles except "you" — used by UtteranceEnd on the system stream
    /// when we don't know which specific speaker finished.
    func sealAllSystemBubbles() {
        for speaker in activeBubbles.keys where speaker != "you" {
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

    // Mic stream is always "you" — ignore the speaker param (no speakerResolver set)
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript t: String, speaker: String?) {
        DispatchQueue.main.async { self.engine?.applyPartial(t, speaker: "you") }
    }
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript t: String, speaker: String?) {
        guard !t.isEmpty else { return }
        DispatchQueue.main.async { self.engine?.applyFinal(t, speaker: "you") }
    }
    func deepgramClient(_ client: DeepgramClient, didReceiveSpeechFinal t: String, speaker: String?) {
        guard !t.isEmpty else { return }
        DispatchQueue.main.async { self.engine?.applyFinal(t, speaker: "you") }
    }
    func deepgramClientDidReceiveUtteranceEnd(_ client: DeepgramClient) {
        // Use debounce instead of immediate seal — the last isFinal chunk may
        // still be in-flight. scheduleSealDebounce will fire after 2s of silence.
        DispatchQueue.main.async { self.engine?.scheduleSealDebounce(for: "you") }
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

    // System stream uses diarization — speaker param comes from speakerResolver,
    // falls back to "Other" if nil (e.g. when diarize hasn't fired yet)
    func deepgramClient(_ client: DeepgramClient, didReceivePartialTranscript t: String, speaker: String?) {
        let label = speaker ?? "Other"
        DispatchQueue.main.async { self.engine?.applyPartial(t, speaker: label) }
    }
    func deepgramClient(_ client: DeepgramClient, didReceiveFinalTranscript t: String, speaker: String?) {
        guard !t.isEmpty else { return }
        let label = speaker ?? "Other"
        DispatchQueue.main.async { self.engine?.applyFinal(t, speaker: label) }
    }
    func deepgramClient(_ client: DeepgramClient, didReceiveSpeechFinal t: String, speaker: String?) {
        guard !t.isEmpty else { return }
        let label = speaker ?? "Other"
        DispatchQueue.main.async { self.engine?.applyFinal(t, speaker: label) }
    }
    func deepgramClientDidReceiveUtteranceEnd(_ client: DeepgramClient) {
        // UtteranceEnd doesn't carry a speaker ID — debounce-seal all open system bubbles
        DispatchQueue.main.async {
            guard let engine = self.engine else { return }
            for speaker in engine.activeBubbles.keys where speaker != "you" {
                engine.scheduleSealDebounce(for: speaker)
            }
        }
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
