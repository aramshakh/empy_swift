//
//  NavigationCoordinatorTests.swift
//  Empy_SwiftTests
//
//  Created by Orchestrator on 2026-03-03.
//  Tests for NavigationCoordinator
//

import XCTest
@testable import Empy_Swift

class NavigationCoordinatorTests: XCTestCase {
    var coordinator: NavigationCoordinator!
    
    override func setUp() {
        super.setUp()
        coordinator = NavigationCoordinator()
    }
    
    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testInitialState() {
        // Then: Should start with empty path (setup screen)
        XCTAssertEqual(coordinator.path.count, 0)
        XCTAssertEqual(coordinator.currentScreen, .setup)
    }
    
    func testNavigateToRecording() {
        // When: Navigate to recording
        coordinator.navigate(to: .recording)
        
        // Then: Path contains recording
        XCTAssertEqual(coordinator.path.count, 1)
        XCTAssertEqual(coordinator.currentScreen, .recording)
    }
    
    func testNavigateToResults() {
        // When: Navigate to results
        let transcript = "Test transcript"
        coordinator.navigate(to: .results(transcript: transcript))
        
        // Then: Path contains results
        XCTAssertEqual(coordinator.path.count, 1)
        
        if case .results(let receivedTranscript) = coordinator.currentScreen {
            XCTAssertEqual(receivedTranscript, transcript)
        } else {
            XCTFail("Expected results screen")
        }
    }
    
    func testGoBack() {
        // Given: Navigate to recording then results
        coordinator.navigate(to: .recording)
        coordinator.navigate(to: .results(transcript: "Test"))
        XCTAssertEqual(coordinator.path.count, 2)
        
        // When: Go back
        coordinator.goBack()
        
        // Then: Back to recording
        XCTAssertEqual(coordinator.path.count, 1)
        XCTAssertEqual(coordinator.currentScreen, .recording)
    }
    
    func testGoBackFromRoot() {
        // Given: At root (empty path)
        XCTAssertEqual(coordinator.path.count, 0)
        
        // When: Try to go back
        coordinator.goBack()
        
        // Then: Still at root
        XCTAssertEqual(coordinator.path.count, 0)
        XCTAssertEqual(coordinator.currentScreen, .setup)
    }
    
    func testReset() {
        // Given: Navigate through multiple screens
        coordinator.navigate(to: .recording)
        coordinator.navigate(to: .results(transcript: "Test"))
        XCTAssertEqual(coordinator.path.count, 2)
        
        // When: Reset
        coordinator.reset()
        
        // Then: Back to root
        XCTAssertEqual(coordinator.path.count, 0)
        XCTAssertEqual(coordinator.currentScreen, .setup)
    }
    
    func testStartRecording() {
        // When: Start recording
        coordinator.startRecording()
        
        // Then: Navigate to recording screen
        XCTAssertEqual(coordinator.path.count, 1)
        XCTAssertEqual(coordinator.currentScreen, .recording)
    }
    
    func testEndRecording() {
        // Given: On recording screen
        coordinator.startRecording()
        
        // When: End recording
        let transcript = "Final transcript"
        coordinator.endRecording(transcript: transcript)
        
        // Then: Navigate to results with transcript
        XCTAssertEqual(coordinator.path.count, 2)
        
        if case .results(let receivedTranscript) = coordinator.currentScreen {
            XCTAssertEqual(receivedTranscript, transcript)
        } else {
            XCTFail("Expected results screen")
        }
    }
    
    func testStartNewSession() {
        // Given: On results screen
        coordinator.navigate(to: .recording)
        coordinator.navigate(to: .results(transcript: "Test"))
        XCTAssertEqual(coordinator.path.count, 2)
        
        // When: Start new session
        coordinator.startNewSession()
        
        // Then: Back to setup
        XCTAssertEqual(coordinator.path.count, 0)
        XCTAssertEqual(coordinator.currentScreen, .setup)
    }
    
    func testFullSessionFlow() {
        // Test complete user flow
        
        // 1. Start at setup
        XCTAssertEqual(coordinator.currentScreen, .setup)
        
        // 2. Start recording
        coordinator.startRecording()
        XCTAssertEqual(coordinator.currentScreen, .recording)
        
        // 3. End recording
        coordinator.endRecording(transcript: "Session transcript")
        if case .results = coordinator.currentScreen {
            // Success
        } else {
            XCTFail("Should be on results")
        }
        
        // 4. Start new session
        coordinator.startNewSession()
        XCTAssertEqual(coordinator.currentScreen, .setup)
    }
}
