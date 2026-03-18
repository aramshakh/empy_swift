//
//  DualStreamManager.swift
//  Empy_Swift
//
//  T04: Coordinates microphone + system audio capture
//  Provides separate callbacks for each audio source
//

import Foundation
import AVFoundation
import Combine

/// Manages dual audio streams: microphone + system audio
/// 
/// **Architecture:**
/// - AudioEngine captures microphone (16kHz mono Int16)
/// - SystemAudioCapture captures system audio (48kHz stereo Float32)
/// - Separate callbacks for each stream
/// - SessionManager receives both streams independently
class DualStreamManager: ObservableObject {
    /// Whether microphone is capturing
    @Published private(set) var isMicCapturing: Bool = false
    
    /// Whether system audio is capturing
    @Published private(set) var isSystemCapturing: Bool = false
    
    /// Callback for microphone audio chunks
    var onMicChunk: ((AudioChunk) -> Void)?
    
    /// Callback for system audio buffers
    var onSystemBuffer: ((AVAudioPCMBuffer) -> Void)?
    
    // Dependencies
    private let audioEngine: AudioEngine
    private let systemAudioCapture: SystemAudioCapture
    private let logger: SessionLogger
    
    // Sequence counters
    private var micSeqId: UInt64 = 0
    private var systemSeqId: UInt64 = 0
    
    init(
        audioEngine: AudioEngine = AudioEngine(),
        systemAudioCapture: SystemAudioCapture = SystemAudioCapture(),
        logger: SessionLogger = .shared
    ) {
        self.audioEngine = audioEngine
        self.systemAudioCapture = systemAudioCapture
        self.logger = logger
        
        // Setup delegates
        systemAudioCapture.delegate = self
        
        // Observe engine state
        audioEngine.$isCapturing
            .assign(to: &$isMicCapturing)
    }
    
    /// Start both audio streams
    /// - Throws: Permission or engine errors
    func start() async throws {
        logger.log(event: "dual_stream_start", layer: "audio")
        
        // Wire microphone callback
        audioEngine.onChunk = { [weak self] chunk in
            self?.onMicChunk?(chunk)
        }
        
        // Start microphone capture
        try audioEngine.start()
        
        // Start system audio capture
        do {
            try await systemAudioCapture.start()
            await MainActor.run {
                self.isSystemCapturing = true
            }
        } catch {
            logger.log(
                event: "system_audio_start_failed",
                layer: "audio",
                details: ["error": error.localizedDescription]
            )
            // Continue with mic-only capture
            print("⚠️ System audio unavailable, continuing with mic only: \(error)")
        }
        
        logger.log(
            event: "dual_stream_started",
            layer: "audio",
            details: [
                "mic_active": "\(isMicCapturing)",
                "system_active": "\(isSystemCapturing)"
            ]
        )
    }
    
    /// Stop both audio streams
    func stop() async {
        logger.log(event: "dual_stream_stop", layer: "audio")
        
        // Stop microphone
        audioEngine.stop()
        
        // Stop system audio
        await systemAudioCapture.stop()
        await MainActor.run {
            self.isSystemCapturing = false
        }
        
        // Reset sequence counters
        micSeqId = 0
        systemSeqId = 0
        
        logger.log(event: "dual_stream_stopped", layer: "audio")
    }
}

// MARK: - SystemAudioCaptureDelegate
extension DualStreamManager: SystemAudioCaptureDelegate {
    func systemAudioDidCapture(buffer: AVAudioPCMBuffer) {
        // Forward buffer to callback
        onSystemBuffer?(buffer)
    }
    
    func systemAudioDidFail(error: Error) {
        logger.log(
            event: "system_audio_error",
            layer: "audio",
            details: ["error": error.localizedDescription]
        )
        
        Task {
            await MainActor.run {
                self.isSystemCapturing = false
            }
        }
        
        // Continue with mic-only capture (graceful degradation)
        print("⚠️ System audio capture failed, continuing with mic only")
    }
}
