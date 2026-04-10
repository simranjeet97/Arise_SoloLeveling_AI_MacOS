import Foundation
import UserNotifications

// MARK: - NotificationService

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[NotificationService] Error requesting auth: \(error.localizedDescription)")
            } else if granted {
                Task { @MainActor in self.scheduleDailyCheckIns() }
            } else {
                print("[NotificationService] Notification permission denied.")
            }
        }
    }

    // MARK: - Scheduling

    private func scheduleDailyCheckIns() {
        center.removeAllPendingNotificationRequests()

        // 1. Morning Check-in (07:30 AM)
        let morningContent = UNMutableNotificationContent()
        morningContent.title = "ARISE: Morning Awakening"
        morningContent.body = "Good morning, Player. How did you sleep? Your first quest awaits."
        morningContent.sound = .default
        morningContent.userInfo = ["actionRoute": "voiceHUD"]

        var morningComps = DateComponents()
        morningComps.hour = 7
        morningComps.minute = 30
        let morningTrigger = UNCalendarNotificationTrigger(dateMatching: morningComps, repeats: true)
        let morningReq = UNNotificationRequest(identifier: "arise.morningCheckIn", content: morningContent, trigger: morningTrigger)

        // 2. Evening Wind-down (10:00 PM)
        let eveningContent = UNMutableNotificationContent()
        eveningContent.title = "ARISE: Dungeons Clearing"
        eveningContent.body = "Player, the day's dungeons are clearing. Take 2 minutes to reflect before you rest."
        eveningContent.sound = .default
        eveningContent.userInfo = ["actionRoute": "journalView"]

        var eveningComps = DateComponents()
        eveningComps.hour = 22
        eveningComps.minute = 0
        let eveningTrigger = UNCalendarNotificationTrigger(dateMatching: eveningComps, repeats: true)
        let eveningReq = UNNotificationRequest(identifier: "arise.eveningWindDown", content: eveningContent, trigger: eveningTrigger)

        // Add
        center.add(morningReq) { error in
            if let e = error { print("[NotificationService] Morning error: \(e.localizedDescription)") }
        }
        center.add(eveningReq) { error in
            if let e = error { print("[NotificationService] Evening error: \(e.localizedDescription)") }
        }

        print("[NotificationService] ✅ Daily notifications scheduled.")
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Intercept clicks on the notification when app is running (or bringing it from background)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let route = userInfo["actionRoute"] as? String

        NotificationCenter.default.post(name: .ariseNotificationTapped, object: route)
        completionHandler()
    }
    
    // Show notification even when app is active
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let ariseNotificationTapped = Notification.Name("ariseNotificationTapped")
}
