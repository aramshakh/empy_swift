//
//  DualStreamManager.swift
//  Empy_Swift
//
//  T04: Coordinates microphone + system audio capture
//  Provides separate callbacks for each audio source
//  ARA-101: DTLN-aec integration for echo cancellation
//

import Foundation
import AVFoundation
import Combine

#if canImport(DTLNAecCoreML)
import DTLNAecCoreML
import DTLNAec256
#endif

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
    
    /// AEC processor (nil if package not available)
    private var aecProcessor: DTLNAecEchoProcessor?
    
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
    
    /// Set the preferred input device. Must be called before startMicOnly().
    func setPreferredInputDevice(_ device: AudioDevice?) {
        audioEngine.preferredInputDevice = device
    }

    /// Start microphone only (synchronous, fast path).
    /// Call this first so Deepgram can connect immediately.
    /// - Throws: Permission or AVAudioEngine errors
    func startMicOnly() throws {
        logger.log(event: "mic_stream_start", layer: "audio")
        
        // Initialize AEC if available
        #if canImport(DTLNAecCoreML)
        if aecProcessor == nil {
            aecProcessor = DTLNAecEchoProcessor(modelSize: .medium)
            do {
                try aecProcessor?.loadModels(from: DTLNAec256.bundle)
                logger.log(event: "aec_loaded", layer: "audio")
                print("🧹 AEC loaded successfully")
            } catch {
                logger.log(event: "aec_load_failed", layer: "audio",
                           details: ["error": error.localizedDescription])
                aecProcessor = nil
                print("⚠️ AEC load failed: \(error.localizedDescription)")
            }
        }
        #else
        logger.log(event: "aec_not_available", layer: "audio")
        print("ℹ️ AEC package not available (add dtln-aec-coreml to enable echo cancellation)")
        #endif
        
        audioEngine.onChunk = { [weak self] chunk in
            guard let self = self else { return }
            
            var processedChunk = chunk
            
            #if canImport(DTLNAecCoreML)
            if let aec = self.aecProcessor {
                // Convert PCM → Float
                let floatSamples = self.pcmDataToFloatArray(chunk.pcmData)
                
                // Process through AEC
                let cleanSamples = aec.processNearEnd(floatSamples)
                
                // Convert back to PCM
                let cleanPCM = self.floatArrayToPCMData(cleanSamples)
                
                processedChunk = AudioChunk(
                    seqId: chunk.seqId,
                    pcmData: cleanPCM,
                    timestamp: chunk.timestamp,
                    source: chunk.source
                )
            }
            #endif
            
            self.onMicChunk?(processedChunk)
        }
        
        try audioEngine.start()
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
            await MainActor.run { self.isSystemCapturing = true }
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
        
        #if canImport(DTLNAecCoreML)
        if let aec = aecProcessor {
            _ = aec.flush()
            aec.resetStates()
        }
        #endif
        
        micSeqId = 0
        systemSeqId = 0
        
        logger.log(event: "dual_stream_stopped", layer: "audio")
    }
}

// MARK: - SystemAudioCaptureDelegate
extension DualStreamManager: SystemAudioCaptureDelegate {
    func systemAudioDidCapture(buffer: AVAudioPCMBuffer) {
        // Feed to AEC as reference signal
        #if canImport(DTLNAecCoreML)
        if let aec = aecProcessor {
            let samples = bufferToFloatArray(buffer)
            aec.feedFarEnd(samples)
        }
        #endif
        
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

// MARK: - AEC Conversion Helpers
#if canImport(DTLNAecCoreML)
private extension DualStreamManager {
    /// Convert AVAudioPCMBuffer to Float array for AEC
    func bufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let floatData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: floatData[0], count: frameLength))
    }
    
    /// Convert PCM Int16 Data to Float array for AEC
    func pcmDataToFloatArray(_ pcmData: Data) -> [Float] {
        let int16Array = pcmData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Int16.self))
        }
        return int16Array.map { Float($0) / 32768.0 }
    }
    
    /// Convert Float array back to PCM Int16 Data
    func floatArrayToPCMData(_ floats: [Float]) -> Data {
        let int16Array = floats.map { sample in
            Int16(max(-32768, min(32767, sample * 32768.0)))
        }
        return Data(bytes: int16Array, count: int16Array.count * MemoryLayout<Int16>.size)
    }
}
#endif
