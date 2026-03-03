//
//  DeviceMonitorTests.swift
//  Empy_SwiftTests
//
//  Refactored: 2026-03-03 (macOS APIs only)
//  Tests for DeviceMonitor audio configuration change handling
//

import XCTest
import AVFoundation
@testable import Empy_Swift

class DeviceMonitorTests: XCTestCase {
    var monitor: DeviceMonitor!
    var mockDelegate: MockDeviceMonitorDelegate!
    var mockLogger: MockSessionLogger!
    var mockEngine: AVAudioEngine!
    
    override func setUp() {
        super.setUp()
        mockLogger = MockSessionLogger()
        monitor = DeviceMonitor(logger: mockLogger)
        mockDelegate = MockDeviceMonitorDelegate()
        monitor.delegate = mockDelegate
        mockEngine = AVAudioEngine()
    }
    
    override func tearDown() {
        monitor.stopMonitoring()
        monitor = nil
        mockDelegate = nil
        mockLogger = nil
        mockEngine = nil
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testMonitoringStartsSuccessfully() {
        // When
        monitor.startMonitoring(engine: mockEngine)
        
        // Then
        XCTAssertEqual(mockLogger.loggedEvents.count, 1)
        XCTAssertEqual(mockLogger.loggedEvents.first?.event, "device_monitoring_started")
        XCTAssertEqual(mockLogger.loggedEvents.first?.layer, "audio")
    }
    
    func testStopMonitoringUnsubscribes() {
        // Given
        monitor.startMonitoring(engine: mockEngine)
        
        // When
        monitor.stopMonitoring()
        
        // Then
        XCTAssertEqual(mockLogger.loggedEvents.count, 2)
        XCTAssertEqual(mockLogger.loggedEvents.last?.event, "device_monitoring_stopped")
    }
    
    func testConfigurationChangeTriggersDelegate() {
        // Given
        monitor.startMonitoring(engine: mockEngine)
        let expectation = XCTestExpectation(description: "Delegate called")
        mockDelegate.onDisconnect = { deviceName in
            XCTAssertFalse(deviceName.isEmpty)
            expectation.fulfill()
        }
        
        // When: Simulate configuration change notification
        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: mockEngine
        )
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockDelegate.disconnectCalled)
    }
    
    func testConfigurationChangeLogsEvent() {
        // Given
        monitor.startMonitoring(engine: mockEngine)
        
        // When: Simulate configuration change
        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: mockEngine
        )
        
        // Then
        // Give notification time to process
        Thread.sleep(forTimeInterval: 0.1)
        
        let configChangeLogs = mockLogger.loggedEvents.filter { $0.event == "device_config_changed" }
        XCTAssertGreaterThan(configChangeLogs.count, 0, "Configuration change should be logged")
        
        if let log = configChangeLogs.first {
            XCTAssertEqual(log.layer, "audio")
            XCTAssertNotNil(log.details?["device"])
            XCTAssertNotNil(log.details?["is_running"])
        }
    }
    
    func testMultipleConfigurationChanges() {
        // Given
        monitor.startMonitoring(engine: mockEngine)
        let expectation = XCTestExpectation(description: "Multiple changes handled")
        expectation.expectedFulfillmentCount = 3
        
        mockDelegate.onDisconnect = { _ in
            expectation.fulfill()
        }
        
        // When: Simulate multiple configuration changes
        for _ in 0..<3 {
            NotificationCenter.default.post(
                name: .AVAudioEngineConfigurationChange,
                object: mockEngine
            )
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(mockDelegate.disconnectCallCount, 3)
    }
    
    func testConfigurationChangeFromDifferentEngineIgnored() {
        // Given
        monitor.startMonitoring(engine: mockEngine)
        let otherEngine = AVAudioEngine()
        
        mockDelegate.onDisconnect = { _ in
            XCTFail("Delegate should not be called for different engine")
        }
        
        // When: Simulate configuration change from different engine
        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: otherEngine
        )
        
        // Then
        let expectation = XCTestExpectation(description: "Wait for potential callback")
        expectation.isInverted = true
        wait(for: [expectation], timeout: 0.5)
        
        XCTAssertFalse(mockDelegate.disconnectCalled)
    }
    
    func testMonitoringAfterStopDoesNotTrigger() {
        // Given
        monitor.startMonitoring(engine: mockEngine)
        monitor.stopMonitoring()
        
        mockDelegate.onDisconnect = { _ in
            XCTFail("Delegate should not be called after stop")
        }
        
        // When: Simulate configuration change after stop
        NotificationCenter.default.post(
            name: .AVAudioEngineConfigurationChange,
            object: mockEngine
        )
        
        // Then
        let expectation = XCTestExpectation(description: "Wait for potential callback")
        expectation.isInverted = true
        wait(for: [expectation], timeout: 0.5)
        
        XCTAssertFalse(mockDelegate.disconnectCalled)
    }
}

// MARK: - Mock Delegate
class MockDeviceMonitorDelegate: DeviceMonitorDelegate {
    var disconnectCalled = false
    var disconnectCallCount = 0
    var onDisconnect: ((String) -> Void)?
    
    func deviceMonitor(_ monitor: DeviceMonitor, didDetectDisconnect deviceName: String) {
        disconnectCalled = true
        disconnectCallCount += 1
        onDisconnect?(deviceName)
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
