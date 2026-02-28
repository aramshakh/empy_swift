//
//  SessionLogger.swift
//  Empy_Swift
//
//  Created by Swift Coder Agent on 2026-02-27.
//  Task: T04 - Structured Logger
//

import Foundation

/// Thread-safe singleton logger for structured session logging.
///
/// Writes log events as JSON lines (JSONL) to `~/Library/Logs/EmpyTrone/{sessionId}.jsonl`.
/// All operations are serialized on a dedicated queue to ensure thread safety.
final class SessionLogger {
    
    // MARK: - Singleton
    
    /// Shared singleton instance
    static let shared = SessionLogger()
    
    // MARK: - Properties
    
    /// Serial queue for thread-safe file operations
    private let queue = DispatchQueue(label: "com.empytrone.sessionlogger", qos: .utility)
    
    /// Current session ID
    private var currentSessionId: String?
    
    /// Current file handle for writing
    private var fileHandle: FileHandle?
    
    /// Session start time for calculating monotonic timestamps
    private var sessionStartTime: Date?
    
    /// Base directory for log files
    private let logsDirectory: URL = {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("EmpyTrone")
    }()
    
    /// JSON encoder configured for compact output
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [] // Compact JSON (single line)
        return encoder
    }()
    
    // MARK: - Initialization
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    // MARK: - Public Methods
    
    /// Starts a new logging session with the specified ID.
    ///
    /// Creates the log directory if needed and opens a new log file.
    /// If a session is already active, it will be ended first.
    ///
    /// - Parameter id: Unique identifier for the session
    func startSession(id: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // End existing session if any
            if self.currentSessionId != nil {
                self._endSession()
            }
            
            self.currentSessionId = id
            self.sessionStartTime = Date()
            
            // Create logs directory if needed
            try? FileManager.default.createDirectory(
                at: self.logsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Create log file
            let logFileURL = self.logsDirectory.appendingPathComponent("\(id).jsonl")
            
            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
            }
            
            // Open file handle for appending
            do {
                self.fileHandle = try FileHandle(forWritingTo: logFileURL)
                self.fileHandle?.seekToEndOfFile()
            } catch {
                print("SessionLogger: Failed to open file handle for session \(id): \(error)")
            }
        }
    }
    
    /// Ends the current logging session.
    ///
    /// Closes the file handle and clears session state.
    func endSession() {
        queue.async { [weak self] in
            self?._endSession()
        }
    }
    
    /// Logs an event to the current session file.
    ///
    /// This method is thread-safe and can be called from any thread.
    /// If no session is active, the log will be silently dropped.
    ///
    /// - Parameter event: The log event to write
    func log(_ event: LogEvent) {
        queue.async { [weak self] in
            guard let self = self,
                  let fileHandle = self.fileHandle else {
                print("SessionLogger: No active session, dropping log event")
                return
            }
            
            do {
                // Encode event to JSON
                let jsonData = try self.encoder.encode(event)
                
                // Write JSON line
                fileHandle.write(jsonData)
                
                // Add newline
                if let newline = "\n".data(using: .utf8) {
                    fileHandle.write(newline)
                }
                
                // Flush to disk (optional, for reliability)
                fileHandle.synchronizeFile()
                
            } catch {
                print("SessionLogger: Failed to encode/write log event: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Internal method to end session (must be called on queue)
    private func _endSession() {
        if let fileHandle = self.fileHandle {
            try? fileHandle.close()
            self.fileHandle = nil
        }
        self.currentSessionId = nil
        self.sessionStartTime = nil
    }
    
    // MARK: - Helper Methods
    
    /// Calculates monotonic time in milliseconds since session start
    ///
    /// - Returns: Milliseconds since session start, or 0 if no session is active
    func monotonicTime() -> Int64 {
        guard let startTime = sessionStartTime else { return 0 }
        return Int64(Date().timeIntervalSince(startTime) * 1000)
    }
    
    /// Gets the current session ID
    ///
    /// - Returns: Current session ID, or nil if no session is active
    func currentSession() -> String? {
        var sessionId: String?
        queue.sync {
            sessionId = self.currentSessionId
        }
        return sessionId
    }
}
