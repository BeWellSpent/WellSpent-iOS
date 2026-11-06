import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import WellSpentREST

/// `@Sendable` closure captures can't mutate a plain local `var` directly —
/// this boxes test-only mutable state so it's still a one-liner to assert on.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@Suite("UnauthenticatedMiddleware")
struct UnauthenticatedMiddlewareTests {
    private func makeRequest() -> HTTPRequest {
        HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/rest/v1/budgets")
    }

    private func makeResponse(_ status: HTTPResponse.Status) -> HTTPResponse {
        HTTPResponse(status: status)
    }

    private let baseURL = URL(string: "https://example.com")!

    @Test("passes a non-401 response through untouched, with no refresh attempted")
    func passesThroughSuccess() async throws {
        let refreshCalls = Box(0)
        let middleware = UnauthenticatedMiddleware(
            refreshAccessToken: { refreshCalls.value += 1; return .refreshed("new-token") },
            onUnauthenticated: { Issue.record("should not fire") }
        )

        let (response, _) = try await middleware.intercept(makeRequest(), body: nil, baseURL: baseURL, operationID: "op") { _, _, _ in
            (self.makeResponse(.ok), nil)
        }

        #expect(response.status == .ok)
        #expect(refreshCalls.value == 0)
    }

    @Test("on 401, refreshes once and retries the original request with the new token")
    func refreshesAndRetriesOnce() async throws {
        let callCount = Box(0)
        let seenAuthHeaders = Box<[String?]>([])
        let unauthenticatedCalled = Box(false)

        let middleware = UnauthenticatedMiddleware(
            refreshAccessToken: { .refreshed("refreshed-token") },
            onUnauthenticated: { unauthenticatedCalled.value = true }
        )

        let (response, _) = try await middleware.intercept(makeRequest(), body: nil, baseURL: baseURL, operationID: "op") { request, _, _ in
            callCount.value += 1
            seenAuthHeaders.value.append(request.headerFields[.authorization])
            return callCount.value == 1 ? (self.makeResponse(.unauthorized), nil) : (self.makeResponse(.ok), nil)
        }

        #expect(response.status == .ok)
        #expect(callCount.value == 2)
        #expect(seenAuthHeaders.value.last == "Bearer refreshed-token")
        #expect(!unauthenticatedCalled.value)
    }

    @Test("falls through to onUnauthenticated, with no retry, when the server rejects the refresh")
    func onUnauthenticatedWhenRefreshFails() async throws {
        let callCount = Box(0)
        let unauthenticatedCalled = Box(false)

        let middleware = UnauthenticatedMiddleware(
            refreshAccessToken: { .rejected },
            onUnauthenticated: { unauthenticatedCalled.value = true }
        )

        let (response, _) = try await middleware.intercept(makeRequest(), body: nil, baseURL: baseURL, operationID: "op") { _, _, _ in
            callCount.value += 1
            return (self.makeResponse(.unauthorized), nil)
        }

        #expect(response.status == .unauthorized)
        #expect(callCount.value == 1)
        #expect(unauthenticatedCalled.value)
    }

    @Test("keeps the session, with no retry, when the refresh merely couldn't complete")
    func keepsSessionWhenRefreshUnavailable() async throws {
        let callCount = Box(0)
        let middleware = UnauthenticatedMiddleware(
            refreshAccessToken: { .unavailable },
            onUnauthenticated: { Issue.record("a network failure must not log the user out") }
        )

        let (response, _) = try await middleware.intercept(makeRequest(), body: nil, baseURL: baseURL, operationID: "op") { _, _, _ in
            callCount.value += 1
            return (self.makeResponse(.unauthorized), nil)
        }

        #expect(response.status == .unauthorized)
        #expect(callCount.value == 1)
    }

    @Test("calls onUnauthenticated, with exactly one retry, when the retried request still 401s")
    func onUnauthenticatedWhenRetryStillFails() async throws {
        let callCount = Box(0)
        let unauthenticatedCalled = Box(false)

        let middleware = UnauthenticatedMiddleware(
            refreshAccessToken: { .refreshed("refreshed-token") },
            onUnauthenticated: { unauthenticatedCalled.value = true }
        )

        let (response, _) = try await middleware.intercept(makeRequest(), body: nil, baseURL: baseURL, operationID: "op") { _, _, _ in
            callCount.value += 1
            return (self.makeResponse(.unauthorized), nil)
        }

        #expect(response.status == .unauthorized)
        #expect(callCount.value == 2) // exactly one retry, never a second
        #expect(unauthenticatedCalled.value)
    }
}

@Suite("isUnauthorizedResponse")
struct IsUnauthorizedResponseTests {
    private func clientError(status: HTTPResponse.Status?) -> ClientError {
        ClientError(
            operationID: "refreshToken", operationInput: (), request: nil, requestBody: nil, baseURL: nil,
            response: status.map { HTTPResponse(status: $0) }, responseBody: nil,
            causeDescription: "test", underlyingError: URLError(.badServerResponse)
        )
    }

    @Test("a 401 that failed to decode still counts; any other status, no response, or foreign error does not")
    func classification() {
        #expect(isUnauthorizedResponse(clientError(status: .unauthorized)))
        #expect(!isUnauthorizedResponse(clientError(status: .internalServerError)))
        #expect(!isUnauthorizedResponse(clientError(status: nil)))
        #expect(!isUnauthorizedResponse(URLError(.notConnectedToInternet)))
    }
}
