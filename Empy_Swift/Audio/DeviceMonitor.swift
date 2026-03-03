//
//  DeviceMonitor.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Monitors audio route changes and detects device disconnections
//

import Foundation
import AVFoundation

/// Delegate protocol for device monitoring events
protocol DeviceMonitorDelegate: AnyObject {
    func deviceMonitor(_ monitor: DeviceMonitor, didDetectDisconnect reason: AVAudioSession.RouteChangeReason)
}

/// Monitors audio input device changes via AVAudioSession notifications
class DeviceMonitor {
    weak var delegate: DeviceMonitorDelegate?
    private let logger: SessionLogger
    
    init(logger: SessionLogger = .shared) {
        self.logger = logger
    }
    
    /// Start monitoring audio route changes
    func startMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        logger.log(event: "device_monitor_started", layer: "audio")
    }
    
    /// Stop monitoring audio route changes
    func stopMonitoring() {
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        logger.log(event: "device_monitor_stopped", layer: "audio")
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        logger.log(
            event: "audio_route_changed",
            layer: "audio",
            details: ["reason": describeReason(reason)]
        )
        
        // Notify delegate only for device disconnections
        switch reason {
        case .oldDeviceUnavailable, .categoryChange:
            delegate?.deviceMonitor(self, didDetectDisconnect: reason)
        default:
            break
        }
    }
    
    private func describeReason(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "new_device_available"
        case .oldDeviceUnavailable: return "old_device_unavailable"
        case .categoryChange: return "category_change"
        case .override: return "override"
        case .wakeFromSleep: return "wake_from_sleep"
        case .noSuitableRouteForCategory: return "no_suitable_route"
        case .routeConfigurationChange: return "route_config_change"
        @unknown default: return "unknown_\(reason.rawValue)"
        }
    }
}
