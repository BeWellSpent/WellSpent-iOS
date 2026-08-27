import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Builds clients for the REST half of the WellSpent API — the endpoints that
/// are global and rarely-changing, and therefore worth letting the system HTTP
/// cache hold.
///
/// The counterpart of `APIClient` in `WellSpentAPI`, and shaped the same way: a
/// public client for endpoints that take no token, and an authenticated one for
/// those that do. Everything else in the API is still ConnectRPC; see
/// `WellSpent-proto/openapi/README.md` for what belongs here.
///
/// `URLSession` does the caching itself. These responses carry `Cache-Control`
/// and `ETag`, so a repeat call is answered from `URLCache` or revalidated with
/// a 304 without any of it appearing in this file — which is the whole reason
/// these endpoints left Connect's unary-POST framing.
public enum RESTClient {
    /// Client with no auth header, for the endpoints that are public by design.
    ///
    /// Used even from authenticated screens when the endpoint itself is public:
    /// sending a token would make the response look user-specific to a cache
    /// that has no way to know otherwise, which throws away the only thing this
    /// transport buys.
    public static func makePublicClient(baseURL: String) -> Client {
        Client(serverURL: url(baseURL), transport: URLSessionTransport())
    }

    /// Client that attaches `Authorization: Bearer <token>` to every request.
    ///
    /// `tokenProvider` is read per request rather than captured once, so a
    /// refreshed token is picked up without rebuilding the client — same
    /// contract as `AuthInterceptor` on the Connect side.
    public static func makeAuthenticatedClient(
        baseURL: String,
        tokenProvider: @escaping @Sendable () -> String?
    ) -> Client {
        Client(
            serverURL: url(baseURL),
            transport: URLSessionTransport(),
            middlewares: [BearerTokenMiddleware(tokenProvider: tokenProvider)]
        )
    }

    private static func url(_ baseURL: String) -> URL {
        // The generated client appends the contract's paths, which already
        // carry their `/rest/v1` prefix, so the server URL is just the host.
        URL(string: baseURL) ?? URL(string: "http://localhost:8080")!
    }
}

/// Adds the bearer token to outbound requests.
struct BearerTokenMiddleware: ClientMiddleware {
    let tokenProvider: @Sendable () -> String?

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = tokenProvider(), !token.isEmpty {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}

// MARK: - Convenience

/// Short names for the contract's schemas, so app code says `StatusBanner`
/// rather than `Components.Schemas.StatusBanner`. The equivalent of the
/// `Wellspent_V1_` types on the Connect side.
public typealias Country = Components.Schemas.Country
public typealias StatusBanner = Components.Schemas.StatusBanner
public typealias StatusBannerSeverity = Components.Schemas.StatusBannerSeverity
public typealias ChangelogItem = Components.Schemas.ChangelogItem
public typealias ChangelogRelease = Components.Schemas.ChangelogRelease
public typealias ChangelogResponse = Components.Schemas.ChangelogResponse
public typealias ChangelogComponent = Components.Schemas.ChangelogComponent
public typealias ChangeType = Components.Schemas.ChangeType

/// Flattens the generated `Input`/`Output` ceremony down to what callers
/// actually want.
///
/// The generated client models every documented response as its own case, which
/// is right for a contract and wrong for a call site. `304` is absent here on
/// purpose: `URLSession` performs revalidation itself and hands back the cached
/// `200`, so the app never sees one.
public extension Client {
    /// The banner currently in effect, or nil when nothing is live.
    func activeStatusBanner() async throws -> StatusBanner? {
        try await getActiveStatusBanner(.init()).ok.body.json.banner
    }

    /// Every enabled country with its feature flags.
    func enabledCountries() async throws -> [Country] {
        try await listCountries(.init()).ok.body.json.countries
    }

    /// Published release notes, plus the version the server is running.
    ///
    /// An empty `components` means every component, which is what the Help
    /// browser wants.
    func changelog(components: [ChangelogComponent] = []) async throws -> ChangelogResponse {
        try await listChangelog(.init(query: .init(component: components.isEmpty ? nil : components)))
            .ok.body.json
    }
}
