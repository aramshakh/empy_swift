import AVFoundation
import ScreenCaptureKit
import Combine
import os.log

/// Dual-stream audio engine for capturing microphone + system audio separately
/// Ported from empy-trone/Recorder.swift lines 388-423 + 250-276
@Observable
final class DualStreamAudioEngine {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "ai.empy.swift", category: "DualStreamAudio")
    
    /// Audio engine instance
    private let engine = AVAudioEngine()
    
    /// Microphone input node
    private var inputNode: AVAudioInputNode { engine.inputNode }
    
    /// Audio format for output files
    private let outputFormat: AVAudioFormat
    
    /// Separate mixers for microphone and system audio
    private let microphoneMixer = AVAudioMixerNode()
    private let systemMixer = AVAudioMixerNode()
    
    /// Player node for system audio
    private let systemAudioPlayerNode = AVAudioPlayerNode()
    
    /// Mute mixer (for monitoring without feedback)
    private let muteMixer = AVAudioMixerNode()
    
    /// ScreenCaptureKit manager for system audio
    private let screenCaptureManager: ScreenCaptureManager
    
    /// Whether engine is running
    private(set) var isRunning = false
    
    /// Callbacks for audio buffers
    var onMicrophoneBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onSystemBuffer: ((AVAudioPCMBuffer) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Create output format (48kHz stereo, Float32)
        self.outputFormat = AudioConstants.standardOutputFormat
        
        // Initialize ScreenCaptureKit manager
        self.screenCaptureManager = ScreenCaptureManager()
        
        // Setup audio engine
        setupAudioEngine()
    }
    
    // MARK: - Setup
    
    /// Setup audio engine with dual-stream architecture
    /// Ported from empy-trone/Recorder.swift lines 388-423
    private func setupAudioEngine() {
        logger.info("Setting up dual-stream audio engine")
        
        // Attach nodes to engine
        engine.attach(microphoneMixer)
        engine.attach(systemMixer)
        engine.attach(systemAudioPlayerNode)
        engine.attach(muteMixer)
        
        // Get microphone input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        logger.info("Microphone input format: \\(inputFormat.sampleRate)Hz, \\(inputFormat.channelCount) channels")
        
        // --- MICROPHONE PATH ---
        // inputNode → microphoneMixer
        engine.connect(inputNode, to: microphoneMixer, format: inputFormat)
        
        // --- SYSTEM AUDIO PATH ---
        // systemAudioPlayerNode → systemMixer
        engine.connect(systemAudioPlayerNode, to: systemMixer, format: outputFormat)
        
        // --- MONITORING PATH (both mixers → output, muted) ---
        // microphoneMixer → muteMixer
        engine.connect(microphoneMixer, to: muteMixer, format: outputFormat)
        
        // systemMixer → muteMixer
        engine.connect(systemMixer, to: muteMixer, format: outputFormat)
        
        // muteMixer → outputNode
        engine.connect(muteMixer, to: engine.outputNode, format: outputFormat)
        
        // --- INSTALL TAPS ---
        installMicrophoneTap()
        installSystemTap()
        
        // Prepare engine
        engine.prepare()
        logger.info("Dual-stream audio engine prepared")
    }
    
    /// Install tap on microphone mixer
    private func installMicrophoneTap() {
        microphoneMixer.installTap(
            onBus: 0,
            bufferSize: AudioConstants.tapBufferSize,
            format: outputFormat
        ) { [weak self] buffer, _ in
            self?.onMicrophoneBuffer?(buffer)
        }
        
        logger.info("Installed tap on microphone mixer")
    }
    
    /// Install tap on system mixer
    private func installSystemTap() {
        systemMixer.installTap(
            onBus: 0,
            bufferSize: AudioConstants.tapBufferSize,
            format: outputFormat
        ) { [weak self] buffer, _ in
            self?.onSystemBuffer?(buffer)
        }
        
        logger.info("Installed tap on system mixer")
    }
    
    // MARK: - Control
    
    /// Start capturing audio (both microphone and system)
    func start() async throws {
        guard !isRunning else {
            logger.warning("Engine already running")
            return
        }
        
        logger.info("Starting dual-stream audio capture...")
        
        // Check microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micStatus == .authorized else {
            if micStatus == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                guard granted else {
                    throw DualStreamError.microphonePermissionDenied
                }
            } else {
                throw DualStreamError.microphonePermissionDenied
            }
        }
        
        // Request screen recording permission
        _ = try await screenCaptureManager.requestPermissions()
        
        // Setup system audio callback
        screenCaptureManager.onAudioBuffer = { [weak self] buffer in
            // Convert to output format if needed
            guard let self = self else { return }
            
            // Schedule buffer to player node
            self.systemAudioPlayerNode.scheduleBuffer(buffer)
            
            // Start player if not already playing
            if !self.systemAudioPlayerNode.isPlaying {
                self.systemAudioPlayerNode.play()
            }
        }
        
        // Start ScreenCaptureKit
        try await screenCaptureManager.startCapture()
        
        // Start audio engine
        try engine.start()
        isRunning = true
        
        logger.info("Dual-stream audio capture started successfully")
    }
    
    /// Stop capturing audio
    func stop() async throws {
        guard isRunning else {
            logger.warning("Engine not running")
            return
        }
        
        logger.info("Stopping dual-stream audio capture...")
        
        // Stop ScreenCaptureKit
        try await screenCaptureManager.stopCapture()
        
        // Stop audio engine
        engine.stop()
        isRunning = false
        
        logger.info("Dual-stream audio capture stopped")
    }
    
    /// Pause audio capture (keeps engine running but stops processing)
    func pause() {
        engine.pause()
        logger.info("Audio capture paused")
    }
    
    /// Resume audio capture
    func resume() throws {
        try engine.start()
        logger.info("Audio capture resumed")
    }
}

// MARK: - Errors

enum DualStreamError: LocalizedError {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case engineStartFailed
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied. Please enable in System Settings > Privacy & Security > Microphone."
        case .screenRecordingPermissionDenied:
            return "Screen recording permission denied. Please enable in System Settings > Privacy & Security > Screen Recording."
        case .engineStartFailed:
            return "Failed to start audio engine"
        }
    }
}
