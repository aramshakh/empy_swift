//
//  SessionManager.swift
//  Empy_Swift
//
//  T16: Session orchestration layer
//  Wires AudioEngine → DeepgramClient → TranscriptEngine
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
    /// Current session state
    @Published private(set) var state: SessionState = .idle
    
    /// Session start time
    @Published private(set) var sessionStartTime: Date?
    
    /// Elapsed recording time
    @Published private(set) var elapsed: TimeInterval = 0
    
    // Dependencies
    private let dualStreamManager: DualStreamManager
    private let deepgramClient: DeepgramClient
    private let transcriptEngine: TranscriptEngine
    private let logger: SessionLogger
    
    // Subscriptions
    private var deepgramCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    
    // Singleton
    static let shared = SessionManager()
    
    init(
        dualStreamManager: DualStreamManager = DualStreamManager(),
        deepgramClient: DeepgramClient = DeepgramClient(),
        logger: SessionLogger = .shared
    ) {
        self.dualStreamManager = dualStreamManager
        self.deepgramClient = deepgramClient
        self.transcriptEngine = TranscriptEngine(
            deepgramClient: deepgramClient,
            logger: logger
        )
        self.logger = logger
        
        // Observe engine failures
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineFailed),
            name: .audioEngineFailed,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTranscriptionDegraded),
            name: .transcriptionDegraded,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public API
    
    /// Start recording session
    func startRecording() {
        if logger.currentSession() == nil {
            logger.startSession(id: UUID().uuidString)
        }
        logger.log(event: "session_start", layer: "session")
        
        // 1. Wire DualStreamManager → DeepgramClient
        // Microphone stream only — system audio uses a separate Deepgram
        // session with different params (48kHz stereo) and is not yet wired.
        // Sending system audio into the mic stream (16kHz mono) breaks transcription.
        dualStreamManager.onMicChunk = { [weak self] chunk in
            self?.deepgramClient.send(audioData: chunk.pcmData)
        }
        
        // 2. Start dual audio capture (async)
        Task {
            do {
                try await dualStreamManager.start()
                
                // 3. Connect transcription after audio is flowing
                try transcriptEngine.startSession()
                
                // 4. Update state
                await MainActor.run {
                    state = .recording
                    sessionStartTime = Date()
                    startTimer()
                }
            } catch {
                logger.log(
                    event: "session_start_failed",
                    layer: "session",
                    details: ["error": error.localizedDescription]
                )
                
                await MainActor.run {
                    state = .idle
                }
            }
        }
    }
    
    /// Stop recording session
    func stopRecording() {
        logger.log(event: "session_stop", layer: "session")
        
        // Stop components
        Task {
            await dualStreamManager.stop()
            await transcriptEngine.endSession()
        }
        
        // Clear subscriptions
        deepgramCancellable?.cancel()
        timerCancellable?.cancel()
        
        // Update state
        state = .stopped
        logger.endSession()
    }
    
    /// Pause recording
    func pauseRecording() {
        logger.log(event: "session_pause", layer: "session")
        
        Task {
            await dualStreamManager.stop()
        }
        state = .paused
        timerCancellable?.cancel()
    }
    
    /// Resume recording
    func resumeRecording() {
        logger.log(event: "session_resume", layer: "session")
        
        Task {
            do {
                try await dualStreamManager.start()
                await MainActor.run {
                    state = .recording
                    startTimer()
                }
            } catch {
                logger.log(
                    event: "session_resume_failed",
                    layer: "session",
                    details: ["error": error.localizedDescription]
                )
            }
        }
    }
    
    /// Get transcript engine for UI observation
    var transcript: TranscriptEngine {
        return transcriptEngine
    }
    
    // MARK: - Private Helpers
    
    private func startTimer() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let start = self.sessionStartTime else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
    }
    
    @objc private func handleAudioEngineFailed() {
        logger.log(event: "session_audio_failed", layer: "session")
        stopRecording()
    }
    
    @objc private func handleTranscriptionDegraded() {
        logger.log(event: "session_transcription_degraded", layer: "session")
        // Continue recording but notify user of transcription issues
    }
}
