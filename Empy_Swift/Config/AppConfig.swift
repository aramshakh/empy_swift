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
    
    /// Log configuration status on startup
    ///
    /// Logs whether Deepgram key is present without exposing the actual value
    static func logStartupConfig() {
        let keyPresent = hasValidDeepgramKey
        print("🔑 Deepgram key present: \(keyPresent)")
    }
}
