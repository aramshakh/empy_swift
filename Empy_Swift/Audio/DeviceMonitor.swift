//
//  DeviceMonitor.swift
//  Empy_Swift
//
//  Refactored: 2026-03-03 (macOS APIs only)
//  Updated: T03 - Device monitoring with disconnect/reconnect detection
//

import AVFoundation

/// Delegate protocol for device monitoring events
protocol DeviceMonitorDelegate: AnyObject {
    func deviceDidDisconnect()
    func deviceDidReconnect()
}

/// Monitors audio device changes and handles disconnect/reconnect events
///
/// **macOS Implementation:** Uses AVAudioEngineConfigurationChange notification
/// to detect device state changes and differentiate between disconnect and reconnect
class DeviceMonitor {
    weak var delegate: DeviceMonitorDelegate?
    
    private let logger: SessionLogger
    private var configObserver: NSObjectProtocol?
    private weak var engine: AVAudioEngine?
    private var wasRunning: Bool = false
    
    init(logger: SessionLogger = .shared) {
        self.logger = logger
    }
    
    deinit {
        stopMonitoring()
    }
    
    /// Start monitoring audio device changes
    /// - Parameter engine: The AVAudioEngine instance to monitor
    func startMonitoring(engine: AVAudioEngine) {
        self.engine = engine
        self.wasRunning = engine.isRunning
        
        // Observe configuration changes (device disconnect, sample rate change, etc.)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] notification in
            self?.handleConfigurationChange(notification)
        }
        
        logger.log(event: "device_monitoring_started", layer: "audio")
    }
    
    /// Stop monitoring audio device changes
    func stopMonitoring() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        
        engine = nil
        logger.log(event: "device_monitoring_stopped", layer: "audio")
    }
    
    /// Handle audio engine configuration changes
    /// Detects disconnect (engine stops) vs reconnect (device available again)
    private func handleConfigurationChange(_ notification: Notification) {
        guard let engine = engine else { return }
        
        let isCurrentlyRunning = engine.isRunning
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        logger.log(
            event: "audio_config_changed",
            layer: "audio",
            details: [
                "was_running": "\(wasRunning)",
                "is_running": "\(isCurrentlyRunning)",
                "channels": "\(format.channelCount)",
                "sample_rate": "\(format.sampleRate)"
            ]
        )
        
        // Detect disconnect: engine was running, now stopped (e.g. device pulled)
        if wasRunning && !isCurrentlyRunning {
            logger.log(event: "mic_disconnected", layer: "audio")
            wasRunning = false
            delegate?.deviceDidDisconnect()
        }
        // Detect reconnect: engine had stopped AND is now also not running (it won't
        // auto-restart), but a real input device is present.
        // We intentionally do NOT treat a format-change notification (where the engine
        // is still running) as a reconnect — that's what SCStream start triggers.
        else if !wasRunning && !isCurrentlyRunning && format.channelCount > 0 {
            logger.log(event: "mic_reconnected", layer: "audio")
            delegate?.deviceDidReconnect()
        }
        // If engine is still running (e.g. SCStream changed the audio graph but the
        // engine kept going), just update wasRunning and do nothing else.
        
        // Update state for next comparison
        wasRunning = isCurrentlyRunning
    }
}
