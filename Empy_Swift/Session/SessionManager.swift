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
    private let conversationManager: ConversationManager
    private let logger: SessionLogger
    
    // Setup data (set by SetupView before recording starts)
    var callType: String = ""
    var participantContext: String = ""
    
    // Subscriptions
    private var deepgramCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    private var transcriptObserver: AnyCancellable?
    private var lastForwardedCount = 0
    
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
        self.conversationManager = ConversationManager()
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

        // 4. Start backend conversation
        lastForwardedCount = 0
        conversationManager.startConversation(
            callType: callType,
            participantContext: participantContext
        )
        
        // 5. Forward final transcript segments to ConversationManager for API batching
        transcriptObserver = transcriptEngine.$transcriptState
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] state in
                guard let self = self else { return }
                let finals = state.segments.filter { $0.isFinal }
                guard finals.count > self.lastForwardedCount else { return }
                
                let newSegments = Array(finals.dropFirst(self.lastForwardedCount))
                self.lastForwardedCount = finals.count
                
                for segment in newSegments {
                    self.conversationManager.addSegment(
                        text: segment.text,
                        speaker: "me",
                        startTime: segment.startTime,
                        endTime: segment.endTime
                    )
                }
            }

        // 6. Update state
        state = .recording
        sessionStartTime = Date()
        startTimer()
    }
    
    /// Stop recording session
    func stopRecording() {
        logger.log(event: "session_stop", layer: "session")
        
        // Stop components
        audioEngine.stop()
        transcriptEngine.endSession()
        
        // Clear subscriptions
        deepgramCancellable?.cancel()
        timerCancellable?.cancel()
        transcriptObserver?.cancel()
        
        // End backend conversation
        conversationManager.endConversation()
        
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
    
    /// Get conversation manager for UI observation
    var conversation: ConversationManager {
        return conversationManager
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
