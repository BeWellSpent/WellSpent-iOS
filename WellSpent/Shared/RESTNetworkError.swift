import Foundation
import os
import OpenAPIRuntime

/// Every REST call site's `catch` block calls `connectivityMessage(for:)` to
/// turn a thrown error into user-facing text — which makes it the one place
/// in the app guaranteed to see every thrown REST failure, network or decode.
/// Logging unconditionally here, rather than asking each of the ~40 call
/// sites to remember its own `AppLogger` call, is what makes "always logs an
/// error" actually true instead of aspirational.
nonisolated enum RESTNetworkError {
    private static let logger = AppLogger.logger("RESTClient")

    /// Maps a thrown connectivity error to the same "can't reach server" text; `nil` for anything else.
    static func connectivityMessage(for error: Error) -> String? {
        log(error)
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

    /// For the other failure shape: the request completed with a response,
    /// but not the one the call site expected (e.g. `guard case .ok = output
    /// else { ... }`) — no error is thrown, so `connectivityMessage` never
    /// sees it. Call sites pass the full `output` so the log captures
    /// whatever status/body the generated type's `description` includes.
    static func logUnexpectedOutput(_ output: Any, operationID: String = #function) {
        logger.error("REST call returned unexpected output operationID=\(operationID, privacy: .public) output=\(String(describing: output), privacy: .public)")
    }

    private static func log(_ error: Error) {
        // `ClientError.description`/`errorDescription` (used by `String(describing:)`
        // and the interpolation below) already include the response status and
        // body, so there's no need to reach into `HTTPResponse` directly here.
        if let clientError = error as? ClientError {
            logger.error("REST call failed operationID=\(clientError.operationID, privacy: .public) error=\(String(describing: error), privacy: .public)")
        } else {
            logger.error("REST call failed error=\(String(describing: error), privacy: .public)")
        }
    }
}
