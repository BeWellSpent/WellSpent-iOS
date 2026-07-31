import Foundation

/// Mirrors the web app's `src/lib/config/features.ts`: a single flat set of
/// on/off switches, gated the same way on both platforms. `googleAuth` is off
/// by default everywhere, same as the web app's `.env.local.example`.
nonisolated enum FeatureFlags {
    static var googleAuthEnabled: Bool {
        isEnabled("FEATURE_GOOGLE_AUTH", in: ProcessInfo.processInfo.environment)
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
