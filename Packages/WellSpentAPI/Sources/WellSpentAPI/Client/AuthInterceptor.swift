import Connect
import Foundation

/// Attaches `Authorization: Bearer <token>` to every outbound request when a token
/// is available, and reports back to the app when the server rejects a request as
/// unauthenticated so the session can be cleared. Direct Swift analog of the web
/// app's two-interceptor chain in `src/lib/api/client.ts`.
final class AuthInterceptor: UnaryInterceptor {
    private let tokenProvider: TokenProvider
    private let onUnauthenticated: UnauthenticatedHandler

    init(tokenProvider: @escaping TokenProvider, onUnauthenticated: @escaping UnauthenticatedHandler) {
        self.tokenProvider = tokenProvider
        self.onUnauthenticated = onUnauthenticated
    }

    func handleUnaryRequest<Message: ProtobufMessage>(
        _ request: HTTPRequest<Message>,
        proceed: @escaping @Sendable (Result<HTTPRequest<Message>, ConnectError>) -> Void
    ) {
        guard let token = tokenProvider(), !token.isEmpty else {
            proceed(.success(request))
            return
        }

        var headers = request.headers
        headers["Authorization"] = ["Bearer \(token)"]
        proceed(.success(HTTPRequest(
            url: request.url,
            headers: headers,
            message: request.message,
            method: request.method,
            trailers: request.trailers,
            idempotencyLevel: request.idempotencyLevel
        )))
    }

    func handleUnaryResponse<Message: ProtobufMessage>(
        _ response: ResponseMessage<Message>,
        proceed: @escaping @Sendable (ResponseMessage<Message>) -> Void
    ) {
        if response.code == .unauthenticated {
            onUnauthenticated()
        }
        proceed(response)
    }
}
