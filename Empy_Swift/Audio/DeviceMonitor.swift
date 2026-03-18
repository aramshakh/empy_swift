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
    /// Called when the active audio device changed while engine was running
    func deviceDidChange()
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
    
    /// Handle audio engine configuration changes.
    ///
    /// Three cases:
    ///   1. Device disconnected: engine was running → now stopped (no input)
    ///   2. Device reconnected: engine was stopped → now channels > 0
    ///   3. Device switched: engine still running but hardware changed → must reinstall tap
    private func handleConfigurationChange(_ notification: Notification) {
        guard let engine = engine else { return }
        
        let isCurrentlyRunning = engine.isRunning
        let format = engine.inputNode.outputFormat(forBus: 0)
        
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
        
        if wasRunning && !isCurrentlyRunning && format.channelCount == 0 {
            // Device physically disconnected — no input available
            wasRunning = false
            delegate?.deviceDidDisconnect()
        } else if !wasRunning && format.channelCount > 0 {
            // Device reconnected after disconnect
            wasRunning = isCurrentlyRunning
            delegate?.deviceDidReconnect()
        } else if wasRunning {
            // Engine still running but configuration changed = device switch
            // (e.g. AirPods ↔ built-in mic, USB mic plugged in)
            delegate?.deviceDidChange()
        }
        
        wasRunning = isCurrentlyRunning
    }
}
