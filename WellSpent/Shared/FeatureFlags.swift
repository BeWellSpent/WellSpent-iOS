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

    /// Strangler-fig cutover switch for the Status+Changelog domain (issue #78/#87). Off by default.
    static var csharpStatusChangelogEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FeatureCSharpStatusChangelog") as? String ?? ""
        return isEnabled("FEATURE_CSHARP_STATUS_CHANGELOG", in: ["FEATURE_CSHARP_STATUS_CHANGELOG": value])
    }

    /// Same pattern, for the Auth domain (issue #87). Off by default.
    static var csharpAuthEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FeatureCSharpAuth") as? String ?? ""
        return isEnabled("FEATURE_CSHARP_AUTH", in: ["FEATURE_CSHARP_AUTH": value])
    }

    /// Same pattern, for the User domain (issue #87). Off by default.
    static var csharpUserEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FeatureCSharpUser") as? String ?? ""
        return isEnabled("FEATURE_CSHARP_USER", in: ["FEATURE_CSHARP_USER": value])
    }

    /// Same pattern, for the Notification domain (issue #87). Off by default.
    static var csharpNotificationEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FeatureCSharpNotification") as? String ?? ""
        return isEnabled("FEATURE_CSHARP_NOTIFICATION", in: ["FEATURE_CSHARP_NOTIFICATION": value])
    }

    /// Same pattern, for the Invite domain (issue #87). Off by default.
    static var csharpInviteEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FeatureCSharpInvite") as? String ?? ""
        return isEnabled("FEATURE_CSHARP_INVITE", in: ["FEATURE_CSHARP_INVITE": value])
    }

    /// Same pattern, for the Plaid domain (issue #87). Off by default.
    static var csharpPlaidEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FeatureCSharpPlaid") as? String ?? ""
        return isEnabled("FEATURE_CSHARP_PLAID", in: ["FEATURE_CSHARP_PLAID": value])
    }

    /// One shared flag for the whole Budget domain (issue #87), unlike every other domain's own
    /// flag — a half-flipped Budget module isn't a coherent deployable state, same reasoning as
    /// web's `csharpBudget`. Covers all 8 planned sub-batches (profile/period, people/
    /// preferences, income/savings, categories/payment methods, transactions, installment/fixed
    /// expenses, allocations/expense summary, transaction review).
    static var csharpBudgetEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "FeatureCSharpBudget") as? String ?? ""
        return isEnabled("FEATURE_CSHARP_BUDGET", in: ["FEATURE_CSHARP_BUDGET": value])
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
