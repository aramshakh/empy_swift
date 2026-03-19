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

    private let callDetector = CallDetector()
    private let callNotifier = CallNotificationManager.shared

    init() {
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
            .onAppear {
                setupCallDetection()
            }
        }
    }

    // MARK: - Call detection wiring

    private func setupCallDetection() {
        // Ask for notification permission once
        callNotifier.requestPermissionIfNeeded()

        // When detector fires → send notification
        callDetector.onCallDetected = { [weak callNotifier, weak callDetector] in
            callNotifier?.sendCallDetectedNotification()
            // Re-arm after cooldown so the detector can fire again next call
            DispatchQueue.main.asyncAfter(deadline: .now() + 25 * 60) {
                callNotifier?.clearCooldownIfExpired()
                callDetector?.resetFired()
            }
        }

        // When user taps "Start Recording" in the notification
        callNotifier.onStartSession = { [weak coordinator, weak sessionManager] in
            guard let coordinator, let sessionManager else { return }
            // Only auto-start if not already in a session
            guard sessionManager.state == .idle || sessionManager.state == .stopped else { return }
            sessionManager.startRecording()
            coordinator.startRecording()
        }

        // Start listening for call activity — only when no session is active
        // We observe sessionManager.state to pause/resume detection accordingly
        callDetector.startMonitoring()
    }
}
