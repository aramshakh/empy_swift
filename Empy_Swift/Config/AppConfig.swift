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
    
    /// User ID sent to backend on conversation create.
    /// Reads from `EMPY_USER_ID` env var, falls back to a stable device-based UUID.
    static var backendUserId: String {
        if let envId = ProcessInfo.processInfo.environment["EMPY_USER_ID"], !envId.isEmpty {
            return envId
        }
        // Persist a stable UUID per device install
        let key = "empy_device_user_id"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    /// Backend auth token for /conversation endpoints
    ///
    /// Reads from `EMPY_BACKEND_TOKEN` environment variable.
    /// Returns `nil` if not set — unauthenticated endpoints work without it.
    static var backendToken: String? {
        let token = ProcessInfo.processInfo.environment["EMPY_BACKEND_TOKEN"] ?? ""
        return token.isEmpty ? nil : token
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
