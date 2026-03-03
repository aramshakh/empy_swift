//
//  NavigationCoordinator.swift
//  Empy_Swift
//
//  Created by Orchestrator on 2026-03-03.
//  Simple enum-based navigation for SwiftUI
//

import SwiftUI
import Combine

/// Screen destinations in the app
enum AppScreen: Hashable {
    case setup
    case recording
    case results(transcript: String)
}

/// Manages app navigation state
class NavigationCoordinator: ObservableObject {
    /// Navigation path (SwiftUI NavigationStack)
    @Published var path: [AppScreen] = []
    
    /// Current screen (computed)
    var currentScreen: AppScreen {
        path.last ?? .setup
    }
    
    // MARK: - Navigation Actions
    
    /// Navigate to a screen
    func navigate(to screen: AppScreen) {
        path.append(screen)
    }
    
    /// Go back one screen
    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
    
    /// Reset to root (setup screen)
    func reset() {
        path.removeAll()
    }
    
    // MARK: - Session Flow Helpers
    
    /// Start recording session
    func startRecording() {
        navigate(to: .recording)
    }
    
    /// End recording, show results
    func endRecording(transcript: String) {
        navigate(to: .results(transcript: transcript))
    }
    
    /// Start new session (from results)
    func startNewSession() {
        reset() // Back to setup
    }
}
