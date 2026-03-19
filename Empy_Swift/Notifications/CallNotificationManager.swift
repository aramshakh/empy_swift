//
//  CallNotificationManager.swift
//  Empy_Swift
//
//  Manages the "Looks like you're on a call" system notification.
//  - Requests UNUserNotification permission on first use
//  - Sends notification only when app is not key window (user can't see it)
//  - Cooldown: 25 minutes after the user ignores a notification
//  - Action button: "Start Recording" → brings app to front + fires onStartSession
//

import Foundation
import UserNotifications
import AppKit

final class CallNotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = CallNotificationManager()

    /// Fired on main thread when the user taps "Start Recording" in the notification.
    var onStartSession: (() -> Void)?

    // MARK: - Constants

    private let notificationID     = "com.empy.call-detected"
    private let categoryID         = "CALL_DETECTED"
    private let startActionID      = "START_RECORDING"
    private let cooldownDuration: TimeInterval = 25 * 60   // 25 minutes
    private let ignoreCooldownKey  = "CallNotificationLastIgnoredDate"

    // MARK: - Init

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategory()
    }

    // MARK: - Permission

    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("⚠️ CallNotificationManager: permission error — \(error.localizedDescription)")
            } else {
                print("🔔 CallNotificationManager: notification permission granted=\(granted)")
            }
        }
    }

    // MARK: - Send notification

    /// Call this when CallDetector fires. Checks:
    /// 1. App is not currently key (user can't see it)
    /// 2. Not within the ignore cooldown window
    func sendCallDetectedNotification() {
        guard !isAppKeyWindow() else {
            print("📵 CallNotificationManager: app is in focus, skipping notification")
            return
        }
        guard !isInCooldown() else {
            print("📵 CallNotificationManager: in cooldown, skipping notification")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Looks like you're on a call"
        content.body  = "Tap to start recording with Empy"
        content.sound = .default
        content.categoryIdentifier = categoryID

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil   // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("⚠️ CallNotificationManager: failed to send — \(error.localizedDescription)")
            } else {
                print("🔔 CallNotificationManager: notification sent")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when user taps a notification action while app is in foreground or background.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier == notificationID else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case startActionID, UNNotificationDefaultActionIdentifier:
            // User tapped "Start Recording" or the notification body itself
            print("✅ CallNotificationManager: user tapped — starting session")
            DispatchQueue.main.async { [weak self] in
                self?.bringAppToFront()
                self?.onStartSession?()
            }

        case UNNotificationDismissActionIdentifier:
            // User explicitly dismissed — start cooldown
            print("🙈 CallNotificationManager: dismissed — starting cooldown")
            startCooldown()

        default:
            // Notification timed out / swiped away without action — start cooldown
            startCooldown()
        }

        completionHandler()
    }

    /// Allow notification banner even when app is in foreground if not key window.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if isAppKeyWindow() {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    // MARK: - Cooldown

    private func startCooldown() {
        UserDefaults.standard.set(Date(), forKey: ignoreCooldownKey)
    }

    private func isInCooldown() -> Bool {
        guard let lastIgnored = UserDefaults.standard.object(forKey: ignoreCooldownKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastIgnored) < cooldownDuration
    }

    func clearCooldownIfExpired() {
        guard let lastIgnored = UserDefaults.standard.object(forKey: ignoreCooldownKey) as? Date,
              Date().timeIntervalSince(lastIgnored) >= cooldownDuration else { return }
        UserDefaults.standard.removeObject(forKey: ignoreCooldownKey)
    }

    // MARK: - Helpers

    private func isAppKeyWindow() -> Bool {
        return NSApp.keyWindow != nil
    }

    private func bringAppToFront() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    private func registerCategory() {
        let startAction = UNNotificationAction(
            identifier: startActionID,
            title: "Start Recording",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [startAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
