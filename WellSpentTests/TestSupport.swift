import Foundation

/// Builds an unsigned JWT string with the given claims — good enough for
/// testing our own payload decoding, since we never verify signatures
/// client-side (that's the server's job).
func makeJWT(subject: String = "user-123", expiresAt: Date?) -> String {
    func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    let header = base64URL(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))

    var claims: [String: Any] = ["sub": subject]
    if let expiresAt {
        claims["exp"] = expiresAt.timeIntervalSince1970
    }
    let payloadData = try! JSONSerialization.data(withJSONObject: claims)
    let payload = base64URL(payloadData)

    return "\(header).\(payload).unsigned-test-signature"
}
