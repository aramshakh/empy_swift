//
//  FeatureFlags.swift
//  Empy_Swift
//
//  Created on 2026-02-27
//  Feature toggle configuration
//

import Foundation

/// Feature flags for toggling app functionality
enum FeatureFlags {
    /// Enable coach cards feature
    ///
    /// When enabled, displays coaching cards in the UI
    static let coachCardsEnabled: Bool = true
    
    /// Enable tension detection feature
    ///
    /// When enabled, activates real-time tension detection in conversations
    static let tensionDetectionEnabled: Bool = true
    
    /// Enable multilingual transcription (code-switching)
    ///
    /// When enabled, Deepgram uses `language=multi` for automatic
    /// language detection and code-switching (e.g. English + Russian).
    /// When disabled, no language param is sent (Deepgram auto-detects
    /// from its general model).
    static let multilingualEnabled: Bool = true
}
