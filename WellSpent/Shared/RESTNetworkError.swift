import Foundation
import OpenAPIRuntime

/// Maps a thrown connectivity error to the same "can't reach server" text; `nil` for anything else.
nonisolated enum RESTNetworkError {
    static func connectivityMessage(for error: Error) -> String? {
        // swift-openapi-runtime wraps every transport failure in ClientError —
        // the real URLError is underlyingError, not the thrown error itself.
        let underlying = (error as? ClientError)?.underlyingError ?? error
        guard let urlError = underlying as? URLError else { return nil }
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
             .timedOut, .networkConnectionLost, .dataNotAllowed:
            return "Can't reach the server. Check your connection and try again."
        default:
            return nil
        }
    }
}
