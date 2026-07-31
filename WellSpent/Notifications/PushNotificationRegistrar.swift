import UIKit
import UserNotifications
import WellSpentAPI

/// Requests notification permission and registers the resulting APNs device
/// token with the backend. Only called after login (`RootView`) — not at
/// cold launch before the user has even authenticated.
enum PushNotificationRegistrar {
    /// Requests permission if never asked before; re-registers (harmless,
    /// upserts by token) if already authorized from a prior session/login.
    /// Does nothing if the user previously denied — iOS won't re-prompt
    /// anyway, and repeatedly calling `registerForRemoteNotifications()`
    /// without authorization is a no-op.
    @MainActor
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        case .authorized, .provisional:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied, .ephemeral:
            break
        @unknown default:
            break
        }
    }

    static func register(deviceToken: Data, authenticatedClient: ProtocolClient) async {
        let tokenString = hexString(from: deviceToken)
        guard !tokenString.isEmpty else { return }

        let client = Wellspent_V1_NotificationServiceClient(client: authenticatedClient)
        _ = await client.registerDeviceToken(request: .with {
            $0.token = tokenString
            $0.platform = "ios"
        })
    }

    /// APNs delivers the device token as raw bytes; the backend (and every
    /// APNs API/tool) expects the lowercase hex string form.
    static func hexString(from deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}
