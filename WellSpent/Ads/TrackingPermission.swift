import AppTrackingTransparency

/// Requests App Tracking Transparency authorization, needed for AdMob to
/// serve personalized (rather than only non-personalized) ads. Mirrors
/// `PushNotificationRegistrar.requestPermissionIfNeeded()`'s shape and
/// "request after login, not at cold launch" posture — asking before the
/// user has even logged in would be a jarring first-run experience.
enum TrackingPermission {
    @MainActor
    static func requestIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }
}
