//
//  ReconnectionStrategy.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Exponential backoff logic for WebSocket reconnection
//

import Foundation

/// Manages reconnection attempts with exponential backoff
struct ReconnectionStrategy {
    private(set) var attempt: Int = 0
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 30.0
    private let maxAttempts: Int = 5
    
    /// Get next delay duration (exponential backoff)
    /// Returns nil if max attempts exceeded
    mutating func nextDelay() -> TimeInterval? {
        guard attempt < maxAttempts else {
            return nil // Max attempts reached
        }
        
        defer { attempt += 1 }
        
        // Exponential: 1s, 2s, 4s, 8s, 16s → cap at 30s
        let delay = min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
        return delay
    }
    
    /// Reset attempt counter (call on successful connection)
    mutating func reset() {
        attempt = 0
    }
    
    /// Check if max attempts reached
    var isExhausted: Bool {
        return attempt >= maxAttempts
    }
}
