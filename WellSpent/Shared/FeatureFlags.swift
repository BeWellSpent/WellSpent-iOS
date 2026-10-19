import Foundation

/// Mirrors the web app's `src/lib/config/features.ts`: a single flat set of
/// on/off switches, gated the same way on both platforms. `googleAuth` is off
/// in Debug, matching the web app's `.env.local.example`; on in Release,
/// matching web's `.env.production`.
///
/// Sourced from `Info.plist`'s `FeatureGoogleAuth` key (`$(FEATURE_GOOGLE_AUTH)`
/// build setting, per-config in `project.pbxproj`) rather than
/// `ProcessInfo.processInfo.environment` — the latter is only populated when
/// Xcode launches the app with an explicit scheme environment variable, which
/// never happens for a TestFlight/App Store-launched process. `APIBaseURL`
/// (`Shared/APIEnvironment.swift`) already established this exact
/// Info.plist-`$(VAR)`-substitution pattern as the one that reliably works in
/// this project.
nonisolated enum FeatureFlags {
    static var googleAuthEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FeatureGoogleAuth") as? String ?? ""
        return isEnabled("FEATURE_GOOGLE_AUTH", in: ["FEATURE_GOOGLE_AUTH": value])
    }

    /// Pure so it's testable without touching `ProcessInfo` — pass any dictionary in.
    static func isEnabled(_ key: String, in environment: [String: String]) -> Bool {
        switch environment[key]?.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}
