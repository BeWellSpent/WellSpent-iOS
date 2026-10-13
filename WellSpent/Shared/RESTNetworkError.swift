import Foundation

/// Maps a thrown connectivity error to the same "can't reach server" text; `nil` for anything else.
nonisolated enum RESTNetworkError {
    static func connectivityMessage(for error: Error) -> String? {
        guard let urlError = error as? URLError else { return nil }
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
             .timedOut, .networkConnectionLost, .dataNotAllowed:
            return "Can't reach the server. Check your connection and try again."
        default:
            return nil
        }
    }
}
