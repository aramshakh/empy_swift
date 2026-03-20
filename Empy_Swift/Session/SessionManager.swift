//
//  SessionManager.swift
//  Empy_Swift
//
//  T16: Session orchestration layer
//  T04: Dual-stream — mic → micClient, system audio → systemClient
//

import Foundation
import Combine
import AVFoundation

/// Session states
enum SessionState {
    case idle
    case recording
    case paused
    case stopped
}

/// Orchestrates audio recording session lifecycle
class SessionManager: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var sessionStartTime: Date?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var chatManager = ChatManager()

    // Dependencies
    private let dualStreamManager: DualStreamManager
    private let micClient:    DeepgramClient
    private let systemClient: DeepgramClient
    private let transcriptEngine: TranscriptEngine
    private let logger: SessionLogger

    private var timerCancellable: AnyCancellable?
    private var processTimer: AnyCancellable?
    private var backendConversationId: String?
    private let apiClient: BackendAPIClient = .shared
    private var lastProcessedTranscriptLength: Int = 0

    // Singleton
    static let shared = SessionManager()

    init(
        dualStreamManager: DualStreamManager = DualStreamManager(),
        logger: SessionLogger = .shared
    ) {
        let mic    = DeepgramClient(logger: logger)
        let system = DeepgramClient(logger: logger)

        self.dualStreamManager = dualStreamManager
        self.micClient    = mic
        self.systemClient = system
        self.transcriptEngine = TranscriptEngine(micClient: mic, systemClient: system, logger: logger)
        self.logger = logger

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAudioEngineFailed),
            name: .audioEngineFailed, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTranscriptionDegraded),
            name: .transcriptionDegraded, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Public API

    func startRecording() {
        if logger.currentSession() == nil {
            logger.startSession(id: UUID().uuidString)
        }
        logger.log(event: "session_start", layer: "session")

        // Create backend conversation (fire-and-forget; falls back gracefully if backend is down)
        Task { await createBackendConversation() }

        // Wire mic chunks → mic Deepgram client
        dualStreamManager.onMicChunk = { [weak self] chunk in
            self?.micClient.send(audioData: chunk.pcmData)
        }

        // Wire system audio → convert → system Deepgram client
        dualStreamManager.onSystemBuffer = { [weak self] buffer in
            guard let self else { return }
            if let pcm16 = self.convertTo16kMono(buffer) {
                self.systemClient.send(audioData: pcm16)
            }
        }

        // Apply preferred input device (resolved from persisted UID)
        let preferredUID = UserDefaults.standard.string(forKey: "preferredInputDeviceUID") ?? ""
        if !preferredUID.isEmpty,
           let device = AudioDeviceManager.shared.resolveDevice(uid: preferredUID) {
            dualStreamManager.setPreferredInputDevice(device)
            logger.log(event: "preferred_input_device_applied", layer: "session",
                       details: ["device": device.name])
        } else {
            dualStreamManager.setPreferredInputDevice(nil)
        }

        // 1. Start mic synchronously
        do {
            try dualStreamManager.startMicOnly()
        } catch {
            logger.log(event: "session_start_failed", layer: "session",
                       details: ["error": error.localizedDescription])
            return
        }

        // 2. Connect mic Deepgram immediately
        do {
            try transcriptEngine.startSession()
        } catch {
            logger.log(event: "session_transcription_start_failed", layer: "session",
                       details: ["error": error.localizedDescription])
            dualStreamManager.stopMic()
            return
        }

        // 3. Update UI state
        state = .recording
        sessionStartTime = Date()
        lastProcessedTranscriptLength = 0
        startTimer()
        startProcessTimer()

        // 4. Start system audio + connect system Deepgram in background.
        // Use the return value directly — avoids a race reading the @Published property
        // from a non-main-thread Task context.
        Task {
            let systemStarted = await dualStreamManager.startSystemAudioIfAvailable()
            if systemStarted {
                do {
                    try transcriptEngine.startSystemStream()
                    print("🔊 System Deepgram stream started")
                } catch {
                    logger.log(event: "system_stream_connect_failed", layer: "session",
                               details: ["error": error.localizedDescription])
                    print("⚠️ System Deepgram stream failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopRecording() {
        logger.log(event: "session_stop", layer: "session")

        let convId = backendConversationId
        Task {
            await dualStreamManager.stop()
            await transcriptEngine.endSession()
            if let id = convId { await endBackendConversation(id: id) }
        }

        processTimer?.cancel()
        processTimer = nil
        timerCancellable?.cancel()
        state = .stopped
        backendConversationId = nil
        logger.endSession()
    }

    func pauseRecording() {
        logger.log(event: "session_pause", layer: "session")
        dualStreamManager.stopMic()
        state = .paused
        timerCancellable?.cancel()
    }

    func resumeRecording() {
        logger.log(event: "session_resume", layer: "session")

        do {
            try dualStreamManager.startMicOnly()
            state = .recording
            startTimer()
            Task { await dualStreamManager.startSystemAudioIfAvailable() }
        } catch {
            logger.log(event: "session_resume_failed", layer: "session",
                       details: ["error": error.localizedDescription])
        }
    }

    var transcript: TranscriptEngine { transcriptEngine }

    // MARK: - Audio conversion: 48kHz stereo Float32 → 16kHz mono Int16

    private lazy var audioConverter: AVAudioConverter? = {
        guard
            let src = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: 48000, channels: 2, interleaved: false),
            let dst = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                    sampleRate: 16000, channels: 1, interleaved: true)
        else { return nil }
        return AVAudioConverter(from: src, to: dst)
    }()

    private func convertTo16kMono(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter = audioConverter else { return nil }

        let inputFrames  = buffer.frameLength
        let ratio        = 16000.0 / 48000.0
        let outputFrames = AVAudioFrameCount(Double(inputFrames) * ratio) + 1

        guard
            let dst = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                    sampleRate: 16000, channels: 1, interleaved: true),
            let outBuf = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: outputFrames)
        else { return nil }

        var conversionError: NSError?
        var inputConsumed = false

        let status = converter.convert(to: outBuf, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return buffer
        }

        guard status != .error, conversionError == nil, outBuf.frameLength > 0 else {
            return nil
        }

        let frameCount = Int(outBuf.frameLength)
        guard let int16Ptr = outBuf.int16ChannelData?[0] else { return nil }
        return Data(bytes: int16Ptr, count: frameCount * MemoryLayout<Int16>.size)
    }

    // MARK: - Timer

    private func startTimer() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.sessionStartTime else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
    }

    @objc private func handleAudioEngineFailed() {
        logger.log(event: "session_audio_failed", layer: "session")
        stopRecording()
    }

    @objc private func handleTranscriptionDegraded() {
        logger.log(event: "session_transcription_degraded", layer: "session")
    }

    // MARK: - Backend conversation lifecycle

    private func createBackendConversation() async {
        let req = ConversationInitRequest(userId: AppConfig.backendUserId)
        do {
            let resp = try await apiClient.createConversation(request: req)
            backendConversationId = resp.conversationId
            await MainActor.run {
                chatManager.initialize(conversationId: resp.conversationId)
            }
            logger.log(event: "backend_conversation_created", layer: "session",
                       details: ["conversation_id": resp.conversationId])
        } catch {
            // Backend down or auth missing — recording still works, /process will be skipped
            logger.log(event: "backend_conversation_create_failed", layer: "session",
                       details: ["error": error.localizedDescription])
            await MainActor.run {
                chatManager.initialize(conversationId: UUID().uuidString)
            }
        }
    }

    private func endBackendConversation(id: String) async {
        do {
            _ = try await apiClient.endConversation(id: id)
            logger.log(event: "backend_conversation_ended", layer: "session",
                       details: ["conversation_id": id])
        } catch {
            logger.log(event: "backend_conversation_end_failed", layer: "session",
                       details: ["error": error.localizedDescription])
        }
    }

    // MARK: - /process timer (every 5s)

    private func startProcessTimer() {
        processTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendTranscriptChunk()
            }
    }

    private func sendTranscriptChunk() {
        guard let convId = backendConversationId else { return }

        let allSegments = transcriptEngine.transcriptState.segments.filter { $0.isFinal }
        let newSegments = allSegments.dropFirst(lastProcessedTranscriptLength)
        guard !newSegments.isEmpty else { return }

        lastProcessedTranscriptLength = allSegments.count

        // Map TranscriptSegment → Transcription
        // Segment index used as stable integer id (backend deduplicates by id)
        let baseIndex = allSegments.count - newSegments.count

        let transcriptions: [Transcription] = newSegments.enumerated().map { offset, seg in
            let speaker = (seg.speaker == "you") ? "me" : "other"
            let timeStart = Int(seg.startTime * 1000)  // seconds → ms
            let timeEnd   = Int(seg.endTime   * 1000)
            return Transcription(
                id: baseIndex + offset,
                text: seg.text,
                timeStart: timeStart,
                timeEnd: timeEnd,
                speaker: speaker
            )
        }

        let request = ProcessRequest(id: convId, conversation: transcriptions)

        Task {
            do {
                let response = try await apiClient.process(request: request)
                logger.log(event: "process_response", layer: "session",
                           details: ["nudge_count": "\(response.nudges.count)"])
                // Surface nudges in UI via chatManager if any returned
                if !response.nudges.isEmpty {
                    await MainActor.run {
                        for nudge in response.nudges {
                            chatManager.receiveNudge(nudge)
                        }
                    }
                }
            } catch {
                logger.log(event: "process_failed", layer: "session",
                           details: ["error": error.localizedDescription])
            }
        }
    }
}
