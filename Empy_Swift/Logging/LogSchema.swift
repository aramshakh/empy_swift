//
//  LogSchema.swift
//  Empy_Swift
//
//  Created by Swift Coder Agent on 2026-02-27.
//  Task: T04 - Structured Logger
//

import Foundation

/// Represents a single log event in structured JSONL format.
///
/// Each log event captures detailed information about system events across
/// different layers (audio, transcription, session, ui) for debugging and monitoring.
struct LogEvent: Codable {
    /// Unique identifier for the current session
    let sessionId: String
    
    /// Event type identifier (e.g., "chunk_emitted", "transcript_received", "state_transition")
    let event: String
    
    /// System layer where the event originated (e.g., "audio", "transcription", "session", "ui")
    let layer: String
    
    /// Source file where the log was generated (for debugging)
    let sourceFile: String
    
    /// Optional sequence ID for ordering events within a session
    let seqId: UInt64?
    
    /// Monotonic time in milliseconds since session start (for precise timing)
    let tMonotonic: Int64
    
    /// Wall-clock timestamp in ISO 8601 format
    let tWall: String
    
    /// Optional byte count (e.g., audio chunk size)
    let bytes: Int?
    
    /// Optional duration in milliseconds (e.g., audio chunk duration)
    let durationMs: Int?
    
    /// Optional state information (e.g., current session state)
    let state: String?
    
    /// Optional metadata as key-value pairs for additional context
    let meta: [String: String]?
    
    /// Creates a new log event with the specified parameters
    init(
        sessionId: String,
        event: String,
        layer: String,
        sourceFile: String = #file,
        seqId: UInt64? = nil,
        tMonotonic: Int64,
        tWall: String = ISO8601DateFormatter().string(from: Date()),
        bytes: Int? = nil,
        durationMs: Int? = nil,
        state: String? = nil,
        meta: [String: String]? = nil
    ) {
        self.sessionId = sessionId
        self.event = event
        self.layer = layer
        self.sourceFile = sourceFile
        self.seqId = seqId
        self.tMonotonic = tMonotonic
        self.tWall = tWall
        self.bytes = bytes
        self.durationMs = durationMs
        self.state = state
        self.meta = meta
    }
}
