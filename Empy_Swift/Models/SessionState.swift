//
//  SessionState.swift
//  Empy_Swift
//
//  Session state machine states for managing session lifecycle.
//

import Foundation

/// Represents all possible states in the session lifecycle
enum SessionState: String, Codable {
    /// Initial state - no session active
    case idle
    
    /// Session is initializing - audio engine starting, WebSocket connecting
    case starting
    
    /// Session is active - audio flowing, transcript updating
    case recording
    
    /// Session is shutting down - cleanup in progress
    case stopping
    
    /// Session completed successfully - report available
    case ended
    
    /// Unrecoverable error occurred
    case error
    
    /// Recording continues but transcript unavailable (degraded mode)
    case degraded
}
