import Foundation
import Testing
@testable import WellSpentAPI

private func makeRequest() -> HTTPRequest<Wellspent_V1_GetMeRequest> {
    HTTPRequest(
        url: URL(string: "http://localhost:8080/wellspent.v1.UserService/GetMe")!,
        headers: [:],
        message: Wellspent_V1_GetMeRequest(),
        method: .post,
        trailers: nil,
        idempotencyLevel: .unknown
    )
}

private func makeResponse(code: Code) -> ResponseMessage<Wellspent_V1_GetMeResponse> {
    let result: Result<Wellspent_V1_GetMeResponse, ConnectError>
    if code == .ok {
        result = .success(Wellspent_V1_GetMeResponse())
    } else {
        result = .failure(ConnectError(code: code, message: "boom"))
    }
    return ResponseMessage(code: code, result: result)
}

@Suite("AuthInterceptor")
struct AuthInterceptorTests {
    @Test("attaches Authorization header when a token is present")
    func attachesHeaderWhenTokenPresent() async throws {
        let interceptor = AuthInterceptor(tokenProvider: { "abc123" }, onUnauthenticated: {})

        let outcome = await withCheckedContinuation { continuation in
            interceptor.handleUnaryRequest(makeRequest()) { result in
                continuation.resume(returning: result)
            }
        }

        let request = try #require(try? outcome.get())
        #expect(request.headers["Authorization"] == ["Bearer abc123"])
    }

    @Test("leaves headers untouched when no token is available")
    func leavesHeadersUntouchedWhenNoToken() async throws {
        let interceptor = AuthInterceptor(tokenProvider: { nil }, onUnauthenticated: {})

        let outcome = await withCheckedContinuation { continuation in
            interceptor.handleUnaryRequest(makeRequest()) { result in
                continuation.resume(returning: result)
            }
        }

        let request = try #require(try? outcome.get())
        #expect(request.headers["Authorization"] == nil)
    }

    @Test("leaves headers untouched when the token is empty")
    func leavesHeadersUntouchedWhenTokenEmpty() async throws {
        let interceptor = AuthInterceptor(tokenProvider: { "" }, onUnauthenticated: {})

        let outcome = await withCheckedContinuation { continuation in
            interceptor.handleUnaryRequest(makeRequest()) { result in
                continuation.resume(returning: result)
            }
        }

        let request = try #require(try? outcome.get())
        #expect(request.headers["Authorization"] == nil)
    }

    @Test("triggers onUnauthenticated when the response code is unauthenticated")
    func triggersCallbackOnUnauthenticatedResponse() async {
        let flagged = Locked(false)
        let interceptor = AuthInterceptor(tokenProvider: { "abc123" }, onUnauthenticated: {
            flagged.value = true
        })

        _ = await withCheckedContinuation { continuation in
            interceptor.handleUnaryResponse(makeResponse(code: .unauthenticated)) { response in
                continuation.resume(returning: response)
            }
        }

        #expect(flagged.value)
    }

    @Test("does not trigger onUnauthenticated for other error codes")
    func doesNotTriggerCallbackForOtherErrors() async {
        let flagged = Locked(false)
        let interceptor = AuthInterceptor(tokenProvider: { "abc123" }, onUnauthenticated: {
            flagged.value = true
        })

        _ = await withCheckedContinuation { continuation in
            interceptor.handleUnaryResponse(makeResponse(code: .invalidArgument)) { response in
                continuation.resume(returning: response)
            }
        }

        #expect(!flagged.value)
    }

    @Test("does not trigger onUnauthenticated for a successful response")
    func doesNotTriggerCallbackForSuccess() async {
        let flagged = Locked(false)
        let interceptor = AuthInterceptor(tokenProvider: { "abc123" }, onUnauthenticated: {
            flagged.value = true
        })

        _ = await withCheckedContinuation { continuation in
            interceptor.handleUnaryResponse(makeResponse(code: .ok)) { response in
                continuation.resume(returning: response)
            }
        }

        #expect(!flagged.value)
    }
}

/// Minimal thread-safe box — the interceptor's callbacks may run off the main
/// thread, so a plain `var` captured by the closure isn't safe under strict
/// concurrency checking.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
