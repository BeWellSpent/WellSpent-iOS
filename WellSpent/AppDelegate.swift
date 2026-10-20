import os
import UIKit
import UserNotifications

/// SwiftUI's `App` protocol has no direct callback for the raw APNs device
/// token — `UIApplicationDelegateAdaptor` is required to receive it. The
/// closures are static (not instance properties) because `WellSpentApp.init()`
/// runs before `@UIApplicationDelegateAdaptor` hands back an instance to hold
/// a reference to; they're set once at app startup and outlive the delegate
/// instance anyway (both live for the process lifetime).
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let logger = AppLogger.logger("AppDelegate")

    static var onDeviceToken: ((Data) -> Void)?
    static var onRegistrationError: ((Error) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set before any push could plausibly arrive — not gated behind
        // login, since the delegate itself has no auth dependency.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AppDelegate.onDeviceToken?(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppDelegate.onRegistrationError?(error)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Push arrived while foregrounded — previously silently dropped (no
    /// delegate was set at all). Publishes the event so the bell/review
    /// badges can refresh, then still shows the banner/sound/badge.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        publishEvent(from: notification.request.content.userInfo, source: "willPresent")
        completionHandler([.banner, .sound, .badge])
    }

    /// User tapped a delivered notification (backgrounded case).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        publishEvent(from: response.notification.request.content.userInfo, source: "didReceive")
        completionHandler()
    }

    private func publishEvent(from userInfo: [AnyHashable: Any], source: String) {
        guard let alertType = userInfo["alertType"] as? String, let budgetProfileID = userInfo["budgetProfileId"] as? String else {
            Self.logger.error("push payload missing alertType/budgetProfileId source=\(source, privacy: .public)")
            return
        }
        Self.logger.info("push event received source=\(source, privacy: .public) alertType=\(alertType, privacy: .public) budgetProfileID=\(budgetProfileID, privacy: .public)")
        PushEventCenter.shared.publish(PushEvent(alertType: alertType, budgetProfileID: budgetProfileID))
    }
}
