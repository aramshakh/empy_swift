//
//  SessionManager.swift
//  Empy_Swift
//
//  T16: Session orchestration layer
//  Wires DualStreamAudioEngine → DeepgramClient → TranscriptEngine
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
    private let dualStreamEngine: DualStreamAudioEngine
    private let deepgramClient: DeepgramClient
    private let transcriptEngine: TranscriptEngine
    private let logger: SessionLogger
    
    // Audio chunk sequencing
    private var micSeqId: UInt64 = 0
    private var systemSeqId: UInt64 = 0
    
    // Subscriptions
    private var deepgramCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    
    // Singleton
    static let shared = SessionManager()
    
    init(
        dualStreamEngine: DualStreamAudioEngine = DualStreamAudioEngine(),
        deepgramClient: DeepgramClient = DeepgramClient(),
        logger: SessionLogger = .shared
    ) {
        self.dualStreamEngine = dualStreamEngine
        self.deepgramClient = deepgramClient
        self.transcriptEngine = TranscriptEngine(
            deepgramClient: deepgramClient,
            logger: logger
        )
        self.logger = logger
        
        // Wire dual-stream callbacks
        setupAudioCallbacks()
        
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
    
    // MARK: - Audio Callbacks Setup
    
    private func setupAudioCallbacks() {
        // Wire microphone buffer callback
        dualStreamEngine.onMicrophoneBuffer = { [weak self] buffer in
            guard let self = self else { return }
            self.handleMicrophoneBuffer(buffer)
        }
        
        // Wire system audio buffer callback
        dualStreamEngine.onSystemBuffer = { [weak self] buffer in
            guard let self = self else { return }
            self.handleSystemBuffer(buffer)
        }
    }
    
    // MARK: - Public API
    
    /// Start recording session
    func startRecording() async throws {
        if logger.currentSession() == nil {
            logger.startSession(id: UUID().uuidString)
        }
        logger.log(event: "session_start", layer: "session")
        
        // Reset sequence IDs
        micSeqId = 0
        systemSeqId = 0
        
        // 1. Start dual-stream audio capture
        try await dualStreamEngine.start()

        // 2. Connect transcription after audio is flowing
        try transcriptEngine.startSession()

        // 3. Update state
        state = .recording
        sessionStartTime = Date()
        startTimer()
    }
    
    /// Stop recording session
    func stopRecording() async {
        logger.log(event: "session_stop", layer: "session")
        
        // Stop dual-stream engine
        do {
            try await dualStreamEngine.stop()
        } catch {
            logger.log(event: "session_stop_error", layer: "session", data: ["error": error.localizedDescription])
        }
        
        // End transcription session async (waits for final transcripts)
        await transcriptEngine.endSession()
        
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
        
        dualStreamEngine.pause()
        state = .paused
        timerCancellable?.cancel()
    }
    
    /// Resume recording
    func resumeRecording() throws {
        logger.log(event: "session_resume", layer: "session")
        
        try dualStreamEngine.resume()
        state = .recording
        startTimer()
    }
    
    /// Get transcript engine for UI observation
    var transcript: TranscriptEngine {
        return transcriptEngine
    }
    
    // MARK: - Audio Buffer Handling
    
    /// Handle microphone audio buffer
    private func handleMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let audioChunk = convertBufferToChunk(buffer, seqId: micSeqId, source: "microphone") else {
            return
        }
        
        // Send to Deepgram (microphone stream)
        deepgramClient.send(audioData: audioChunk.pcmData)
        
        // Increment sequence ID
        micSeqId += 1
        
        logger.log(event: "mic_chunk_sent", layer: "audio", data: [
            "seqId": String(audioChunk.seqId),
            "bytes": String(audioChunk.byteCount)
        ])
    }
    
    /// Handle system audio buffer
    private func handleSystemBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let audioChunk = convertBufferToChunk(buffer, seqId: systemSeqId, source: "system") else {
            return
        }
        
        // TODO: Send to separate Deepgram connection for system audio
        // For now, just log
        systemSeqId += 1
        
        logger.log(event: "system_chunk_received", layer: "audio", data: [
            "seqId": String(audioChunk.seqId),
            "bytes": String(audioChunk.byteCount)
        ])
    }
    
    /// Convert AVAudioPCMBuffer to AudioChunk
    private func convertBufferToChunk(_ buffer: AVAudioPCMBuffer, seqId: UInt64, source: String) -> AudioChunk? {
        guard let channelData = buffer.floatChannelData else {
            logger.log(event: "buffer_conversion_failed", layer: "audio", data: ["source": source])
            return nil
        }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Convert Float32 PCM to Data
        // Note: Deepgram expects 16-bit PCM, but we're sending Float32 for now
        // TODO: Convert to 16-bit signed little-endian PCM
        var pcmData = Data()
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                var sampleData = sample
                pcmData.append(Data(bytes: &sampleData, count: MemoryLayout<Float32>.size))
            }
        }
        
        // Calculate elapsed time
        let elapsed = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let elapsedMs = Int64(elapsed * 1000)
        
        return AudioChunk(
            seqId: seqId,
            pcmData: pcmData,
            sessionElapsedMs: elapsedMs,
            byteCount: pcmData.count
        )
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
        Task {
            await stopRecording()
        }
    }
    
    @objc private func handleTranscriptionDegraded() {
        logger.log(event: "session_transcription_degraded", layer: "session")
        // Continue recording but notify user of transcription issues
    }
}
