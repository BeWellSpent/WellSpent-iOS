import UIKit

/// SwiftUI's `App` protocol has no direct callback for the raw APNs device
/// token — `UIApplicationDelegateAdaptor` is required to receive it. The
/// closures are static (not instance properties) because `WellSpentApp.init()`
/// runs before `@UIApplicationDelegateAdaptor` hands back an instance to hold
/// a reference to; they're set once at app startup and outlive the delegate
/// instance anyway (both live for the process lifetime).
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var onDeviceToken: ((Data) -> Void)?
    static var onRegistrationError: ((Error) -> Void)?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AppDelegate.onDeviceToken?(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppDelegate.onRegistrationError?(error)
    }
}
