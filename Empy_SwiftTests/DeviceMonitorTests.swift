//
//  DeviceMonitorTests.swift
//  Empy_SwiftTests
//
//  Created by Orchestrator on 2026-03-03.
//  Tests for DeviceMonitor audio route change handling
//

import XCTest
import AVFoundation
@testable import Empy_Swift

class DeviceMonitorTests: XCTestCase {
    var monitor: DeviceMonitor!
    var mockDelegate: MockDeviceMonitorDelegate!
    var mockLogger: MockSessionLogger!
    
    override func setUp() {
        super.setUp()
        mockLogger = MockSessionLogger()
        monitor = DeviceMonitor(logger: mockLogger)
        mockDelegate = MockDeviceMonitorDelegate()
        monitor.delegate = mockDelegate
    }
    
    override func tearDown() {
        monitor.stopMonitoring()
        monitor = nil
        mockDelegate = nil
        mockLogger = nil
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testMonitoringStartsSuccessfully() {
        // When
        monitor.startMonitoring()
        
        // Then
        XCTAssertEqual(mockLogger.loggedEvents.count, 1)
        XCTAssertEqual(mockLogger.loggedEvents.first?.event, "device_monitor_started")
        XCTAssertEqual(mockLogger.loggedEvents.first?.layer, "audio")
    }
    
    func testStopMonitoringUnsubscribes() {
        // Given
        monitor.startMonitoring()
        
        // When
        monitor.stopMonitoring()
        
        // Then
        XCTAssertEqual(mockLogger.loggedEvents.count, 2)
        XCTAssertEqual(mockLogger.loggedEvents.last?.event, "device_monitor_stopped")
    }
    
    func testRouteChangeNotificationTriggersDelegate() {
        // Given
        monitor.startMonitoring()
        let expectation = XCTestExpectation(description: "Delegate called")
        mockDelegate.onDisconnect = { reason in
            XCTAssertEqual(reason, .oldDeviceUnavailable)
            expectation.fulfill()
        }
        
        // When
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            ]
        )
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockDelegate.disconnectCalled)
    }
    
    func testCategoryChangeTriggersDelegate() {
        // Given
        monitor.startMonitoring()
        let expectation = XCTestExpectation(description: "Delegate called for category change")
        mockDelegate.onDisconnect = { reason in
            XCTAssertEqual(reason, .categoryChange)
            expectation.fulfill()
        }
        
        // When
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue
            ]
        )
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockDelegate.disconnectCalled)
    }
    
    func testNewDeviceAvailableDoesNotTriggerDelegate() {
        // Given
        monitor.startMonitoring()
        mockDelegate.onDisconnect = { _ in
            XCTFail("Delegate should not be called for new device available")
        }
        
        // When
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
            ]
        )
        
        // Then
        // Wait a bit to ensure delegate is not called
        let expectation = XCTestExpectation(description: "Wait for potential callback")
        expectation.isInverted = true
        wait(for: [expectation], timeout: 0.5)
        
        XCTAssertFalse(mockDelegate.disconnectCalled)
    }
    
    func testRouteChangeLogsEvent() {
        // Given
        monitor.startMonitoring()
        
        // When
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            ]
        )
        
        // Then
        // Give notification time to process
        Thread.sleep(forTimeInterval: 0.1)
        
        let routeChangeLogs = mockLogger.loggedEvents.filter { $0.event == "audio_route_changed" }
        XCTAssertGreaterThan(routeChangeLogs.count, 0, "Route change should be logged")
        
        if let log = routeChangeLogs.first {
            XCTAssertEqual(log.layer, "audio")
            XCTAssertNotNil(log.details?["reason"])
        }
    }
}

// MARK: - Mock Delegate
class MockDeviceMonitorDelegate: DeviceMonitorDelegate {
    var disconnectCalled = false
    var onDisconnect: ((AVAudioSession.RouteChangeReason) -> Void)?
    
    func deviceMonitor(_ monitor: DeviceMonitor, didDetectDisconnect reason: AVAudioSession.RouteChangeReason) {
        disconnectCalled = true
        onDisconnect?(reason)
    }
}

// MARK: - Mock Logger
class MockSessionLogger: SessionLogger {
    struct LogEntry {
        let event: String
        let layer: String
        let details: [String: String]?
    }
    
    var loggedEvents: [LogEntry] = []
    
    override func log(event: String, layer: String, details: [String: String]? = nil) {
        loggedEvents.append(LogEntry(event: event, layer: layer, details: details))
    }
}
