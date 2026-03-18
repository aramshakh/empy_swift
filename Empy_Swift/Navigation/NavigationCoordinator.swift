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
    case results(messages: [TranscriptMessage])
}

/// Manages app navigation state
class NavigationCoordinator: ObservableObject {
    @Published var path: [AppScreen] = []
    
    var currentScreen: AppScreen {
        path.last ?? .setup
    }
    
    // MARK: - Navigation Actions
    
    func navigate(to screen: AppScreen) {
        path.append(screen)
    }
    
    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
    
    func reset() {
        path.removeAll()
    }
    
    // MARK: - Session Flow Helpers
    
    func startRecording() {
        navigate(to: .recording)
    }
    
    /// End recording — pass the full dialogue as structured messages
    func endRecording(messages: [TranscriptMessage]) {
        navigate(to: .results(messages: messages))
    }
    
    func startNewSession() {
        reset()
    }
}
