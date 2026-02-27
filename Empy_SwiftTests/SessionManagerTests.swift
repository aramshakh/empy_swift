//
//  SessionManagerTests.swift
//  Empy_SwiftTests
//
//  Tests for SessionManager state machine transitions.
//

import XCTest
@testable import Empy_Swift

final class SessionManagerTests: XCTestCase {
    var sessionManager: SessionManager!
    
    override func setUp() {
        super.setUp()
        sessionManager = SessionManager()
    }
    
    override func tearDown() {
        sessionManager = nil
        super.tearDown()
    }
    
    // MARK: - Valid Transitions (7 total)
    
    func testValidTransition_IdleToStarting() {
        // Given: idle state
        XCTAssertEqual(sessionManager.state, .idle)
        
        // When: transition to starting
        let result = sessionManager.transition(to: .starting)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .starting)
    }
    
    func testValidTransition_StartingToRecording() {
        // Given: starting state
        sessionManager.transition(to: .starting)
        
        // When: transition to recording
        let result = sessionManager.transition(to: .recording)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .recording)
    }
    
    func testValidTransition_StartingToError() {
        // Given: starting state
        sessionManager.transition(to: .starting)
        
        // When: transition to error
        let result = sessionManager.transition(to: .error)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testValidTransition_RecordingToStopping() {
        // Given: recording state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        
        // When: transition to stopping
        let result = sessionManager.transition(to: .stopping)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .stopping)
    }
    
    func testValidTransition_RecordingToError() {
        // Given: recording state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        
        // When: transition to error
        let result = sessionManager.transition(to: .error)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testValidTransition_RecordingToDegraded() {
        // Given: recording state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        
        // When: transition to degraded
        let result = sessionManager.transition(to: .degraded)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .degraded)
    }
    
    func testValidTransition_DegradedToRecording() {
        // Given: degraded state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .degraded)
        
        // When: transition back to recording
        let result = sessionManager.transition(to: .recording)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .recording)
    }
    
    func testValidTransition_DegradedToStopping() {
        // Given: degraded state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .degraded)
        
        // When: transition to stopping
        let result = sessionManager.transition(to: .stopping)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .stopping)
    }
    
    func testValidTransition_DegradedToError() {
        // Given: degraded state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .degraded)
        
        // When: transition to error
        let result = sessionManager.transition(to: .error)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testValidTransition_StoppingToEnded() {
        // Given: stopping state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        
        // When: transition to ended
        let result = sessionManager.transition(to: .ended)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .ended)
    }
    
    func testValidTransition_StoppingToError() {
        // Given: stopping state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        
        // When: transition to error
        let result = sessionManager.transition(to: .error)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testValidTransition_EndedToIdle() {
        // Given: ended state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        sessionManager.transition(to: .ended)
        
        // When: transition to idle
        let result = sessionManager.transition(to: .idle)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .idle)
    }
    
    func testValidTransition_ErrorToIdle() {
        // Given: error state
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .error)
        
        // When: transition to idle
        let result = sessionManager.transition(to: .idle)
        
        // Then: transition succeeds
        XCTAssertTrue(result)
        XCTAssertEqual(sessionManager.state, .idle)
    }
    
    // MARK: - Invalid Transitions from idle (6 invalid)
    
    func testInvalidTransition_IdleToRecording() {
        let result = sessionManager.transition(to: .recording)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .idle)
    }
    
    func testInvalidTransition_IdleToStopping() {
        let result = sessionManager.transition(to: .stopping)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .idle)
    }
    
    func testInvalidTransition_IdleToEnded() {
        let result = sessionManager.transition(to: .ended)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .idle)
    }
    
    func testInvalidTransition_IdleToError() {
        let result = sessionManager.transition(to: .error)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .idle)
    }
    
    func testInvalidTransition_IdleToDegraded() {
        let result = sessionManager.transition(to: .degraded)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .idle)
    }
    
    func testInvalidTransition_IdleToIdle() {
        let result = sessionManager.transition(to: .idle)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .idle)
    }
    
    // MARK: - Invalid Transitions from starting (5 invalid)
    
    func testInvalidTransition_StartingToIdle() {
        sessionManager.transition(to: .starting)
        let result = sessionManager.transition(to: .idle)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .starting)
    }
    
    func testInvalidTransition_StartingToStarting() {
        sessionManager.transition(to: .starting)
        let result = sessionManager.transition(to: .starting)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .starting)
    }
    
    func testInvalidTransition_StartingToStopping() {
        sessionManager.transition(to: .starting)
        let result = sessionManager.transition(to: .stopping)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .starting)
    }
    
    func testInvalidTransition_StartingToEnded() {
        sessionManager.transition(to: .starting)
        let result = sessionManager.transition(to: .ended)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .starting)
    }
    
    func testInvalidTransition_StartingToDegraded() {
        sessionManager.transition(to: .starting)
        let result = sessionManager.transition(to: .degraded)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .starting)
    }
    
    // MARK: - Invalid Transitions from recording (4 invalid)
    
    func testInvalidTransition_RecordingToIdle() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        let result = sessionManager.transition(to: .idle)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .recording)
    }
    
    func testInvalidTransition_RecordingToStarting() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        let result = sessionManager.transition(to: .starting)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .recording)
    }
    
    func testInvalidTransition_RecordingToRecording() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        let result = sessionManager.transition(to: .recording)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .recording)
    }
    
    func testInvalidTransition_RecordingToEnded() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        let result = sessionManager.transition(to: .ended)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .recording)
    }
    
    // MARK: - Invalid Transitions from degraded (4 invalid)
    
    func testInvalidTransition_DegradedToIdle() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .degraded)
        let result = sessionManager.transition(to: .idle)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .degraded)
    }
    
    func testInvalidTransition_DegradedToStarting() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .degraded)
        let result = sessionManager.transition(to: .starting)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .degraded)
    }
    
    func testInvalidTransition_DegradedToDegraded() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .degraded)
        let result = sessionManager.transition(to: .degraded)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .degraded)
    }
    
    func testInvalidTransition_DegradedToEnded() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .degraded)
        let result = sessionManager.transition(to: .ended)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .degraded)
    }
    
    // MARK: - Invalid Transitions from stopping (5 invalid)
    
    func testInvalidTransition_StoppingToIdle() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        let result = sessionManager.transition(to: .idle)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .stopping)
    }
    
    func testInvalidTransition_StoppingToStarting() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        let result = sessionManager.transition(to: .starting)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .stopping)
    }
    
    func testInvalidTransition_StoppingToRecording() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        let result = sessionManager.transition(to: .recording)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .stopping)
    }
    
    func testInvalidTransition_StoppingToStopping() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        let result = sessionManager.transition(to: .stopping)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .stopping)
    }
    
    func testInvalidTransition_StoppingToDegraded() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        let result = sessionManager.transition(to: .degraded)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .stopping)
    }
    
    // MARK: - Invalid Transitions from ended (6 invalid)
    
    func testInvalidTransition_EndedToStarting() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        sessionManager.transition(to: .ended)
        let result = sessionManager.transition(to: .starting)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .ended)
    }
    
    func testInvalidTransition_EndedToRecording() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        sessionManager.transition(to: .ended)
        let result = sessionManager.transition(to: .recording)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .ended)
    }
    
    func testInvalidTransition_EndedToStopping() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        sessionManager.transition(to: .ended)
        let result = sessionManager.transition(to: .stopping)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .ended)
    }
    
    func testInvalidTransition_EndedToEnded() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        sessionManager.transition(to: .ended)
        let result = sessionManager.transition(to: .ended)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .ended)
    }
    
    func testInvalidTransition_EndedToError() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        sessionManager.transition(to: .ended)
        let result = sessionManager.transition(to: .error)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .ended)
    }
    
    func testInvalidTransition_EndedToDegraded() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .recording)
        sessionManager.transition(to: .stopping)
        sessionManager.transition(to: .ended)
        let result = sessionManager.transition(to: .degraded)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .ended)
    }
    
    // MARK: - Invalid Transitions from error (6 invalid)
    
    func testInvalidTransition_ErrorToStarting() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .error)
        let result = sessionManager.transition(to: .starting)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testInvalidTransition_ErrorToRecording() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .error)
        let result = sessionManager.transition(to: .recording)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testInvalidTransition_ErrorToStopping() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .error)
        let result = sessionManager.transition(to: .stopping)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testInvalidTransition_ErrorToEnded() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .error)
        let result = sessionManager.transition(to: .ended)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testInvalidTransition_ErrorToError() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .error)
        let result = sessionManager.transition(to: .error)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
    
    func testInvalidTransition_ErrorToDegraded() {
        sessionManager.transition(to: .starting)
        sessionManager.transition(to: .error)
        let result = sessionManager.transition(to: .degraded)
        XCTAssertFalse(result)
        XCTAssertEqual(sessionManager.state, .error)
    }
}
