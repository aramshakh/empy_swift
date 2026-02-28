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
}
