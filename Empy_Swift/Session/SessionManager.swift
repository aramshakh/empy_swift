//
//  SessionManager.swift
//  Empy_Swift
//
//  T16: Session orchestration layer
//  Wires AudioEngine → DeepgramClient → TranscriptEngine
//

import Foundation
import Combine

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
    private let audioEngine: AudioEngine
    private let deepgramClient: DeepgramClient
    private let transcriptEngine: TranscriptEngine
    private let logger: SessionLogger
    
    // Subscriptions
    private var deepgramCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    
    // Singleton
    static let shared = SessionManager()
    
    init(
        audioEngine: AudioEngine = AudioEngine(),
        deepgramClient: DeepgramClient = DeepgramClient(),
        logger: SessionLogger = .shared
    ) {
        self.audioEngine = audioEngine
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
    func startRecording() throws {
        if logger.currentSession() == nil {
            logger.startSession(id: UUID().uuidString)
        }
        logger.log(event: "session_start", layer: "session")
        
        // 1. Wire AudioEngine → DeepgramClient
        audioEngine.onChunk = { [weak self] chunk in
            self?.deepgramClient.send(audioData: chunk.pcmData)
        }
        
        // 2. Start audio capture first
        try audioEngine.start()

        // 3. Connect transcription after audio is flowing
        try transcriptEngine.startSession()

        // 4. Update state
        state = .recording
        sessionStartTime = Date()
        startTimer()
    }
    
    /// Stop recording session
    func stopRecording() {
        logger.log(event: "session_stop", layer: "session")
        
        // Stop components
        audioEngine.stop()
        
        // End transcription session async (waits for final transcripts)
        Task {
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
        
        audioEngine.stop()
        state = .paused
        timerCancellable?.cancel()
    }
    
    /// Resume recording
    func resumeRecording() throws {
        logger.log(event: "session_resume", layer: "session")
        
        try audioEngine.start()
        state = .recording
        startTimer()
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
