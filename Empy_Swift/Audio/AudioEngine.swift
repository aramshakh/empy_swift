//
//  AudioEngine.swift
//  Empy_Swift
//
//  Refactored: 2026-03-03 (macOS APIs only)
//  Port of empy-trone Recorder.swift audio capture
//

import AVFoundation
import Combine

extension Notification.Name {
    static let audioEngineFailed = Notification.Name("audioEngineFailed")
}

/// Audio engine for capturing microphone input and emitting PCM chunks
/// 
/// **macOS Implementation:** Uses AVAudioEngine directly without AVAudioSession
/// (AVAudioSession is iOS-only and does not exist on macOS)
class AudioEngine: ObservableObject {
    /// Whether the engine is currently capturing audio
    @Published var isCapturing: Bool = false
    
    /// Callback invoked when an audio chunk is ready
    var onChunk: ((AudioChunk) -> Void)?
    
    /// AVAudioEngine instance
    private let engine = AVAudioEngine()
    
    /// Chunk emitter for buffering and emitting audio chunks
    private var chunkEmitter: ChunkEmitter?
    
    /// Device monitor for handling audio route changes
    private let deviceMonitor: DeviceMonitor
    
    /// Session logger for event tracking
    private let logger: SessionLogger
    
    /// Audio format: 16kHz, mono, Int16 PCM
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true  // macOS uses interleaved
    )
    
    init(logger: SessionLogger = .shared) {
        self.logger = logger
        self.deviceMonitor = DeviceMonitor(logger: logger)
        deviceMonitor.delegate = self
    }
    
    /// Start capturing audio from the microphone
    /// - Throws: Audio engine errors or permission errors
    func start() throws {
        // Check microphone permission (macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            try setupEngine()
            
        case .notDetermined:
            // Request permission asynchronously
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        do {
                            try self?.setupEngine()
                        } catch {
                            print("❌ Failed to setup engine: \(error)")
                            self?.logger.log(
                                event: "engine_setup_failed",
                                layer: "audio",
                                details: ["error": error.localizedDescription]
                            )
                        }
                    } else {
                        print("⚠️ Microphone permission denied")
                        self?.logger.log(event: "mic_permission_denied", layer: "audio")
                    }
                }
            }
            
        case .denied, .restricted:
            logger.log(event: "mic_permission_denied", layer: "audio")
            throw NSError(
                domain: "AudioEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"]
            )
            
        @unknown default:
            throw NSError(
                domain: "AudioEngine",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown permission status"]
            )
        }
        
        // Start device monitoring
        deviceMonitor.startMonitoring(engine: engine)
    }
    
    /// Setup and start the audio engine
    private func setupEngine() throws {
        guard let targetFormat = targetFormat else {
            throw NSError(
                domain: "AudioEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"]
            )
        }
        
        let inputNode = engine.inputNode
        
        // Remove any stale tap before touching the node
        inputNode.removeTap(onBus: 0)
        
        // Start the engine FIRST so inputNode reflects the real hardware format
        try engine.start()
        
        // Read the actual hardware format AFTER engine start
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        logger.log(
            event: "engine_setup",
            layer: "audio",
            details: [
                "input_sample_rate": "\(inputFormat.sampleRate)",
                "input_channels": "\(inputFormat.channelCount)",
                "target_sample_rate": "\(targetFormat.sampleRate)"
            ]
        )
        
        // Create chunk emitter for microphone
        let emitter = ChunkEmitter(source: .microphone)
        emitter.onChunk = { [weak self] chunk in
            self?.onChunk?(chunk)
        }
        self.chunkEmitter = emitter
        
        // Install tap with the real hardware format — no mismatch possible
        // Buffer size: ~100ms at 16kHz = 1600 frames
        let bufferSize: AVAudioFrameCount = 1600
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let emitter = self.chunkEmitter else { return }
            
            guard let convertedBuffer = self.convert(buffer: buffer, to: targetFormat) else {
                return
            }
            guard let pcmData = self.extractPCMData(from: convertedBuffer) else {
                return
            }
            emitter.append(samples: pcmData)
        }
        
        DispatchQueue.main.async {
            self.isCapturing = true
        }
        
        logger.log(event: "engine_started", layer: "audio")
        print("✅ Audio engine started")
    }
    
    /// Convert an audio buffer to the target format
    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // If formats match, no conversion needed
        if buffer.format == format {
            return buffer
        }
        
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return nil
        }
        
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("⚠️ Conversion error: \(error)")
            return nil
        }
        
        convertedBuffer.frameLength = convertedBuffer.frameCapacity
        return convertedBuffer
    }
    
    /// Extract PCM data from an audio buffer
    private func extractPCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let byteCount = frameLength * channelCount * MemoryLayout<Int16>.size
        
        // For interleaved format (macOS default)
        if buffer.format.isInterleaved {
            let ptr = channelData[0]
            // Convert Int16 pointer to raw bytes
            let data = Data(bytes: ptr, count: byteCount)
            return data
        } else {
            // Non-interleaved: merge channels
            var data = Data(capacity: byteCount)
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    let sample = channelData[channel][frame]
                    withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
                }
            }
            return data
        }
    }
    
    /// Stop capturing audio
    func stop() {
        deviceMonitor.stopMonitoring()
        
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        
        chunkEmitter = nil
        
        DispatchQueue.main.async {
            self.isCapturing = false
        }
        
        logger.log(event: "engine_stopped", layer: "audio")
        print("🛑 Audio engine stopped")
    }
}

// MARK: - DeviceMonitorDelegate
extension AudioEngine: DeviceMonitorDelegate {
    func deviceDidDisconnect() {
        logger.log(event: "mic_disconnected", layer: "audio")
        
        // Stop recording gracefully (no crash)
        if isCapturing {
            stop()
        }
    }
    
    func deviceDidReconnect() {
        logger.log(event: "mic_reconnected", layer: "audio")
        
        // Auto-restart recording
        do {
            try start()
        } catch {
            logger.log(
                event: "restart_failed_on_reconnect",
                layer: "audio",
                details: ["error": error.localizedDescription]
            )
        }
    }
}
