import Foundation

/// Supplies the current access token for an outbound request, or `nil` if the user
/// is logged out. Kept as a plain closure (rather than a protocol) so it can be
/// backed directly by a Keychain read without pulling any `@Observable` session
/// type into this networking-only package.
public typealias TokenProvider = @Sendable () -> String?

/// Invoked when the server reports the current token is no longer valid
/// (HTTP 401 / Connect `.unauthenticated`), so the app can clear the session.
public typealias UnauthenticatedHandler = @Sendable () -> Void
