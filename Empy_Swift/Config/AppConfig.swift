//
//  AppConfig.swift
//  Empy_Swift
//
//  Created on 2026-02-27
//  Central application configuration
//

import Foundation

/// Central configuration for the Empy application
enum AppConfig {
    /// Deepgram API key from environment or fallback demo key
    ///
    /// Reads from `EMPY_DEEPGRAM_KEY` environment variable.
    /// Falls back to a placeholder demo key if not set.
    ///
    /// - Warning: Replace "DEMO_KEY_REPLACE_ME" with actual key before production use
    static var deepgramApiKey: String {
        if let envKey = ProcessInfo.processInfo.environment["EMPY_DEEPGRAM_KEY"], !envKey.isEmpty {
            return envKey
        }
        return "DEMO_KEY_REPLACE_ME"
    }
    
    /// Check if a valid Deepgram API key is configured
    ///
    /// Returns `false` if using the demo placeholder key
    static var hasValidDeepgramKey: Bool {
        let key = deepgramApiKey
        return key != "DEMO_KEY_REPLACE_ME" && !key.isEmpty
    }
    
    /// Empy backend API base URL
    ///
    /// Reads from `EMPY_API_URL` environment variable.
    /// Falls back to localhost:8081 for development.
    static var empyAPIBaseURL: String {
        if let envURL = ProcessInfo.processInfo.environment["EMPY_API_URL"], !envURL.isEmpty {
            return envURL
        }
        return "http://localhost:8081"
    }
    
    /// User ID for API calls
    ///
    /// Reads from `EMPY_USER_ID` environment variable.
    /// Falls back to a process-based identifier.
    static var userId: String {
        if let envId = ProcessInfo.processInfo.environment["EMPY_USER_ID"], !envId.isEmpty {
            return envId
        }
        return "swift-user-\(ProcessInfo.processInfo.processIdentifier)"
    }
    
    /// Log configuration status on startup
    ///
    /// Logs whether Deepgram key is present without exposing the actual value
    static func logStartupConfig() {
        let keyPresent = hasValidDeepgramKey
        print("Deepgram key present: \(keyPresent)")
        print("API base URL: \(empyAPIBaseURL)")
    }
}
