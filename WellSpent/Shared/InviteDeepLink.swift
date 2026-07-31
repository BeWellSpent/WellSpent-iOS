import Foundation

/// Extracts an invite token from a Universal Link. The backend always emails
/// `{FRONTEND_URL}/en/invite/{token}` (hardcoded locale, not iOS's concern),
/// but this also accepts other locale prefixes and a bare `/invite/{token}`
/// path for robustness.
nonisolated enum InviteDeepLink {
    static func token(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2, components[components.count - 2] == "invite" else { return nil }
        return components.last
    }
}
