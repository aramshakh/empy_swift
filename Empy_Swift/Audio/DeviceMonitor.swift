//
//  DeviceMonitor.swift
//  Empy_Swift
//
//  Refactored: 2026-03-03 (macOS APIs only)
//  Port of empy-trone device monitoring
//

import AVFoundation

/// Delegate protocol for device monitoring events
protocol DeviceMonitorDelegate: AnyObject {
    func deviceMonitor(_ monitor: DeviceMonitor, didDetectDisconnect deviceName: String)
}

/// Monitors audio device changes and disconnects
///
/// **macOS Implementation:** Uses AVAudioEngineConfigurationChange notification
/// instead of iOS AVAudioSession route change notifications
class DeviceMonitor {
    weak var delegate: DeviceMonitorDelegate?
    
    private let logger: SessionLogger
    private var configObserver: NSObjectProtocol?
    private weak var engine: AVAudioEngine?
    
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
    private func handleConfigurationChange(_ notification: Notification) {
        guard let engine = engine else { return }
        
        let inputNode = engine.inputNode
        let deviceName = inputNode.outputFormat(forBus: 0).channelCount > 0
            ? "Audio Input Device"
            : "Unknown Device"
        
        logger.log(
            event: "device_config_changed",
            layer: "audio",
            details: [
                "device": deviceName,
                "is_running": "\(engine.isRunning)"
            ]
        )
        
        // Notify delegate about potential disconnect
        delegate?.deviceMonitor(self, didDetectDisconnect: deviceName)
    }
}
