import Foundation

/// Minimal, dependency-free JWT payload reader. Decodes only the middle
/// (payload) segment to read `sub`/`exp` claims for local expiry checks —
/// it never verifies the signature, since that's the server's job. This is
/// purely for UI state (show the authenticated screen vs. the login screen),
/// the direct Swift port of the web app's `isTokenExpired` in `token.ts`.
nonisolated enum JWT {
    struct Claims: Equatable {
        let subject: String?
        let expiresAt: Date?

        /// A token with no `exp` claim is treated as expired — fail closed,
        /// never trust an unbounded session.
        var isExpired: Bool {
            guard let expiresAt else { return true }
            return expiresAt <= Date()
        }
    }

    static func decode(_ token: String) -> Claims? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, let payloadData = base64URLDecode(String(segments[1])) else {
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }

        let subject = json["sub"] as? String
        let expiresAt = (json["exp"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        return Claims(subject: subject, expiresAt: expiresAt)
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        guard !value.isEmpty else { return nil }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: paddingLength)
        return Data(base64Encoded: base64)
    }
}
