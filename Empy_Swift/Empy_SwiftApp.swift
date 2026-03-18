//
//  Empy_SwiftApp.swift
//  Empy_Swift
//
//  Created by Aram on 27.02.26.
//

import SwiftUI

@main
struct Empy_SwiftApp: App {
    @StateObject private var coordinator = NavigationCoordinator()
    @StateObject private var sessionManager = SessionManager.shared
    
    init() {
        // Log configuration status on startup
        AppConfig.logStartupConfig()
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $coordinator.path) {
                SetupView()
                    .navigationDestination(for: AppScreen.self) { screen in
                        switch screen {
                        case .setup:
                            SetupView()
                        case .recording:
                            RecordingView()
                        case .results(let messages):
                            ResultsView(messages: messages)
                        }
                    }
            }
            .environmentObject(coordinator)
            .environmentObject(sessionManager)
            .environmentObject(sessionManager.transcript)
        }
    }
}
