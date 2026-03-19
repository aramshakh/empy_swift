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
    private var conditionalAEC: ConditionalAEC?
    
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
        
        // Setup conditional AEC (will be initialized after engine starts)
        conditionalAEC = nil  // Created lazily in startMicOnly()
    }
    
    /// Set the preferred input device. Must be called before startMicOnly().
    func setPreferredInputDevice(_ device: AudioDevice?) {
        audioEngine.preferredInputDevice = device
    }

    /// Start microphone only (synchronous, fast path).
    /// Call this first so Deepgram can connect immediately.
    /// - Throws: Permission or AVAudioEngine errors
    func startMicOnly() throws {
        logger.log(event: "mic_stream_start", layer: "audio")
        
        audioEngine.onChunk = { [weak self] chunk in
            self?.onMicChunk?(chunk)
        }
        
        try audioEngine.start()
        
        // Initialize conditional AEC after engine starts
        if conditionalAEC == nil {
            conditionalAEC = ConditionalAEC(
                engine: audioEngine.engine,
                logger: logger
            )
        }
        
        // Enable AEC in mic-only mode (system audio not started yet)
        conditionalAEC?.update(systemAudioActive: false)
        
        logger.log(event: "mic_stream_started", layer: "audio")
        print("🎙️ Mic capture started")
    }
    
    /// Stop microphone (synchronous).
    func stopMic() {
        audioEngine.stop()
    }
    
    /// Start system audio capture in the background.
    /// Non-critical — failure is logged and ignored.
    /// Delayed by 1s to let AVAudioEngine fully initialise before SCStream
    /// touches the audio server (prevents 'nope'/kAudioUnitErr_FormatNotSupported).
    /// - Returns: `true` if system audio started successfully, `false` otherwise.
    @discardableResult
    func startSystemAudioIfAvailable() async -> Bool {
        // Give AVAudioEngine 1 second to stabilise before SCStream starts
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        do {
            try await systemAudioCapture.start()
            await MainActor.run {
                self.isSystemCapturing = true
                // Disable AEC when system audio starts capturing
                self.conditionalAEC?.update(systemAudioActive: true)
            }
            logger.log(event: "system_audio_started", layer: "audio")
            print("🔊 System audio capture started")
            return true
        } catch {
            logger.log(event: "system_audio_start_failed", layer: "audio",
                       details: ["error": error.localizedDescription])
            print("⚠️ System audio unavailable, mic-only: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Stop both audio streams
    func stop() async {
        logger.log(event: "dual_stream_stop", layer: "audio")
        
        audioEngine.stop()
        
        await systemAudioCapture.stop()
        await MainActor.run { self.isSystemCapturing = false }
        
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
