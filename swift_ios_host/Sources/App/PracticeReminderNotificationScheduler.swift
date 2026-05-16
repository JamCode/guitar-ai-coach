import Foundation
import UIKit
import UserNotifications

enum PracticeReminderNotificationScheduler {
    static let dailyReminderIdentifier = "daily-ear-training-reminder"
    static let reminderHour = 20
    static let reminderMinute = 0

    static func configureDailyReminder() {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    scheduleDailyReminder(on: center)
                }
            case .authorized, .provisional, .ephemeral:
                scheduleDailyReminder(on: center)
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    static func scheduleDailyReminder(on center: UNUserNotificationCenter = .current()) {
        let request = makeDailyReminderRequest()
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
        center.add(request)
    }

    static func makeDailyReminderRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = AppL10n.t("ear_training_reminder_title")
        content.body = AppL10n.t("ear_training_reminder_body")
        content.sound = .default
        content.userInfo = ["destination": "practice"]

        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        return UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )
    }
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
