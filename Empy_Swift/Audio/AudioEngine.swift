//
//  AudioEngine.swift
//  Empy_Swift
//
//  Refactored: 2026-03-03 (macOS APIs only)
//  Port of empy-trone Recorder.swift audio capture
//

import AVFoundation
import Combine
import ScreenCaptureKit

extension Notification.Name {
    static let audioEngineFailed = Notification.Name("audioEngineFailed")
}

/// Audio engine for capturing microphone input and emitting PCM chunks
/// 
/// **macOS Implementation:** Uses AVAudioEngine directly without AVAudioSession
/// (AVAudioSession is iOS-only and does not exist on macOS)
class AudioEngine: NSObject, ObservableObject {
    /// Whether the engine is currently capturing audio
    @Published var isCapturing: Bool = false
    
    /// Callback invoked when an audio chunk is ready
    var onChunk: ((AudioChunk) -> Void)?
    
    /// AVAudioEngine instance
    private let engine = AVAudioEngine()
    
    /// Chunk emitter for microphone stream
    private var chunkEmitter: ChunkEmitter?
    
    /// Chunk emitter for system audio stream
    private var systemChunkEmitter: ChunkEmitter?
    
    /// ScreenCaptureKit stream for system audio capture
    @available(macOS 12.3, *)
    private var screenCaptureStream: SCStream?
    
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
    
    /// Configuration change observer
    private var configObserver: NSObjectProtocol?
    
    init(logger: SessionLogger = .shared) {
        self.logger = logger
        self.deviceMonitor = DeviceMonitor(logger: logger)
        super.init()
        deviceMonitor.delegate = self
    }
    
    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        
        // Create chunk emitters
        let emitter = ChunkEmitter()
        emitter.onChunk = { [weak self] chunk in
            self?.onChunk?(chunk)
        }
        self.chunkEmitter = emitter
        
        let systemEmitter = ChunkEmitter()
        systemEmitter.onChunk = { [weak self] chunk in
            self?.onChunk?(chunk)
        }
        self.systemChunkEmitter = systemEmitter
        
        // Install tap on input node
        // Buffer size: ~100ms at target sample rate = 1600 frames
        let bufferSize: AVAudioFrameCount = 1600
        
        // CRITICAL FIX: Remove existing tap to prevent crash
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let emitter = self.chunkEmitter else { return }
            
            // Convert audio buffer to target format
            guard let convertedBuffer = self.convert(buffer: buffer, to: targetFormat) else {
                return
            }
            
            // Extract PCM data from the buffer
            guard let pcmData = self.extractPCMData(from: convertedBuffer) else {
                return
            }
            
            // Append microphone chunk
            emitter.append(samples: pcmData, source: .microphone)
        }
        
        // Observe configuration changes (device disconnect, sample rate change)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
        
        // Start the engine
        try engine.start()
        
        // Start system audio capture (best effort; microphone keeps working if this fails)
        if #available(macOS 12.3, *) {
            startSystemAudioCapture()
        } else {
            logger.log(event: "system_audio_unavailable_os", layer: "audio")
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
    
    @available(macOS 12.3, *)
    private func startSystemAudioCapture() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }

                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 16_000
                config.channelCount = 1

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
                self.screenCaptureStream = stream
                try await stream.startCapture()

                self.logger.log(event: "system_audio_started", layer: "audio")
            } catch {
                self.logger.log(
                    event: "system_audio_start_failed",
                    layer: "audio",
                    details: ["error": error.localizedDescription]
                )
            }
        }
    }

    @available(macOS 12.3, *)
    private func stopSystemAudioCapture() {
        guard let stream = screenCaptureStream else { return }
        Task {
            try? await stream.stopCapture()
        }
        screenCaptureStream = nil
        systemChunkEmitter = nil
    }

    /// Stop capturing audio
    func stop() {
        deviceMonitor.stopMonitoring()
        if #available(macOS 12.3, *) {
            stopSystemAudioCapture()
        }
        
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        
        chunkEmitter = nil
        
        DispatchQueue.main.async {
            self.isCapturing = false
        }
        
        logger.log(event: "engine_stopped", layer: "audio")
        print("🛑 Audio engine stopped")
    }
    
    /// Handle audio engine configuration changes (device disconnect, sample rate change)
    private func handleConfigurationChange() {
        logger.log(event: "engine_config_changed", layer: "audio")
        
        // Configuration change often means device disconnect
        // Attempt to restart engine
        do {
            try restartEngine()
        } catch {
            logger.log(
                event: "engine_restart_failed",
                layer: "audio",
                details: ["error": error.localizedDescription]
            )
            
            // Notify SessionManager about failure
            NotificationCenter.default.post(name: .audioEngineFailed, object: nil)
            
            DispatchQueue.main.async {
                self.isCapturing = false
            }
        }
    }
    
    /// Restart the audio engine (used after device disconnect)
    private func restartEngine() throws {
        logger.log(event: "engine_restart_attempt", layer: "audio")
        
        // Stop current engine
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        
        chunkEmitter = nil
        
        // Small delay to allow system to settle
        Thread.sleep(forTimeInterval: 0.1)
        
        // Restart with new default device
        try setupEngine()
        
        logger.log(event: "engine_restart_success", layer: "audio")
    }
}

// MARK: - ScreenCaptureKit
@available(macOS 12.3, *)
extension AudioEngine: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.log(
            event: "system_audio_stream_stopped",
            layer: "audio",
            details: ["error": error.localizedDescription]
        )
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }
        guard let emitter = systemChunkEmitter else { return }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        var copyStatus: OSStatus = noErr
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            copyStatus = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }

        guard copyStatus == noErr else {
            logger.log(
                event: "system_audio_copy_failed",
                layer: "audio",
                details: ["status": "\(copyStatus)"]
            )
            return
        }

        emitter.append(samples: data, source: .system)
    }
}

// MARK: - DeviceMonitorDelegate
extension AudioEngine: DeviceMonitorDelegate {
    func deviceMonitor(_ monitor: DeviceMonitor, didDetectDisconnect deviceName: String) {
        logger.log(
            event: "device_disconnect",
            layer: "audio",
            details: ["device": deviceName]
        )
        
        // Attempt to restart engine with new default device
        do {
            try restartEngine()
            logger.log(event: "device_failover_success", layer: "audio")
        } catch {
            logger.log(
                event: "device_failover_failed",
                layer: "audio",
                details: ["error": error.localizedDescription]
            )
            
            // Notify SessionManager about failure
            NotificationCenter.default.post(name: .audioEngineFailed, object: nil)
            
            // Stop capturing state
            DispatchQueue.main.async {
                self.isCapturing = false
            }
        }
    }
}
