import Foundation

/// The running app's version as shown to the user: `v1.35.3 (7)`.
///
/// Both halves are needed, and neither substitutes for the other.
/// `MARKETING_VERSION` (`CFBundleShortVersionString`) only moves when a
/// release is deliberately cut, so on its own it cannot tell two builds of the
/// same version apart — which is exactly the question being asked when someone
/// reports a bug from TestFlight. `CURRENT_PROJECT_VERSION` (`CFBundleVersion`)
/// is bumped once per feature, so it answers "which build am I running?".
///
/// Falls back to the marketing version alone if the build number is missing,
/// rather than rendering an empty parenthesis.
nonisolated enum AppVersion {
    /// `MARKETING_VERSION` alone. This is what a changelog release is keyed
    /// on — a changelog entry describes a release a reader was *given*, and the
    /// build number moves every feature while the marketing version
    /// deliberately does not.
    static var marketingVersion: String? {
        guard let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !marketing.isEmpty else { return nil }
        return marketing
    }

    static var displayText: String? {
        guard let marketing = marketingVersion else { return nil }
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              !build.isEmpty else { return "v\(marketing)" }
        return "v\(marketing) (\(build))"
    }
}
