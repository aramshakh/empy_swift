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
        // Microphone stream
        dualStreamManager.onMicChunk = { [weak self] chunk in
            self?.deepgramClient.send(audioData: chunk.pcmData)
        }
        
        // System audio stream
        dualStreamManager.onSystemBuffer = { [weak self] buffer in
            // Convert Float32 buffer to Data
            if let pcmData = self?.convertBufferToData(buffer) {
                self?.deepgramClient.send(audioData: pcmData)
            }
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
    
    /// Convert AVAudioPCMBuffer to PCM Data
    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Convert Float32 to Int16 PCM
        var int16Data = [Int16]()
        int16Data.reserveCapacity(frameLength * channelCount)
        
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                // Clamp and convert to Int16
                let clampedSample = max(-1.0, min(1.0, sample))
                let int16Sample = Int16(clampedSample * Float(Int16.max))
                int16Data.append(int16Sample)
            }
        }
        
        // Convert to Data
        return int16Data.withUnsafeBytes { Data($0) }
    }
    
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
