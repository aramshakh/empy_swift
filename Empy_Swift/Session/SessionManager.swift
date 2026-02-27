//
//  SessionManager.swift
//  Empy_Swift
//
//  Manages session lifecycle using a finite state machine.
//

import Foundation
import Combine

/// Manages session state transitions using a finite state machine
class SessionManager: ObservableObject {
    /// Current session state
    @Published private(set) var state: SessionState = .idle
    
    /// Legal state transitions map
    /// Key: from state, Value: set of valid destination states
    private let legalTransitions: [SessionState: Set<SessionState>] = [
        .idle: [.starting],
        .starting: [.recording, .error],
        .recording: [.stopping, .error, .degraded],
        .degraded: [.recording, .stopping, .error],
        .stopping: [.ended, .error],
        .ended: [.idle],
        .error: [.idle]
    ]
    
    /// Attempts to transition to a new state
    /// - Parameter newState: The target state
    /// - Returns: true if transition was successful, false if illegal
    @discardableResult
    func transition(to newState: SessionState) -> Bool {
        // Check if transition is legal
        guard let validStates = legalTransitions[state],
              validStates.contains(newState) else {
            print("❌ [SessionManager] Illegal transition: \(state.rawValue) -> \(newState.rawValue)")
            return false
        }
        
        // Log the transition
        print("✅ [SessionManager] Transition: \(state.rawValue) -> \(newState.rawValue)")
        
        // Update state
        state = newState
        return true
    }
    
    /// Resets the session manager to idle state (for testing)
    func reset() {
        state = .idle
        print("🔄 [SessionManager] Reset to idle")
    }
}
