@_exported import Connect
import Foundation
@_exported import SwiftProtobuf

/// Builds `ProtocolClient`s for talking to the WellSpent backend. Mirrors the
/// web app's `src/lib/api/client.ts`: a `publicClient` for pre-login RPCs
/// (Register, Login, ListCountries, GetBudgetInvite, ...) and an authenticated
/// client that attaches the bearer token and reacts to a 401 by clearing the
/// session, built per `makeAuthenticatedClient`.
public enum APIClient {
    /// Client with no auth interceptor — used for RPCs that are public by design
    /// (see the bypass list mirrored from the backend's `cmd/server/main.go`).
    public static func makePublicClient(baseURL: String) -> ProtocolClient {
        ProtocolClient(config: config(baseURL: baseURL, interceptors: []))
    }

    /// Client that attaches `Authorization: Bearer <token>` to every request via
    /// `tokenProvider`, and invokes `onUnauthenticated` when the server rejects a
    /// request as unauthenticated (expired/invalid token).
    public static func makeAuthenticatedClient(
        baseURL: String,
        tokenProvider: @escaping TokenProvider,
        onUnauthenticated: @escaping UnauthenticatedHandler
    ) -> ProtocolClient {
        let interceptors: [InterceptorFactory] = [
            InterceptorFactory { _ in
                AuthInterceptor(tokenProvider: tokenProvider, onUnauthenticated: onUnauthenticated)
            }
        ]
        return ProtocolClient(config: config(baseURL: baseURL, interceptors: interceptors))
    }

    private static func config(baseURL: String, interceptors: [InterceptorFactory]) -> ProtocolClientConfig {
        ProtocolClientConfig(
            host: baseURL,
            networkProtocol: .connect,
            codec: ProtoCodec(),
            interceptors: interceptors
        )
    }
}
