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

    // Dependencies
    private let dualStreamManager: DualStreamManager
    private let micClient:    DeepgramClient
    private let systemClient: DeepgramClient
    private let transcriptEngine: TranscriptEngine
    private let logger: SessionLogger

    private var timerCancellable: AnyCancellable?

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
        startTimer()

        // 4. Start system audio + connect system Deepgram in background
        Task {
            await dualStreamManager.startSystemAudioIfAvailable()
            // Connect system Deepgram only after SCStream is running
            if dualStreamManager.isSystemCapturing {
                do {
                    try transcriptEngine.startSystemStream()
                } catch {
                    logger.log(event: "system_stream_connect_failed", layer: "session",
                               details: ["error": error.localizedDescription])
                }
            }
        }
    }

    func stopRecording() {
        logger.log(event: "session_stop", layer: "session")

        Task {
            await dualStreamManager.stop()
            await transcriptEngine.endSession()
        }

        timerCancellable?.cancel()
        state = .stopped
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
}
