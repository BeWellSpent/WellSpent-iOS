import Foundation
import Testing
import WellSpentAPI

@testable import WellSpent

@Suite("AppleAuthCoordinator")
struct AppleAuthCoordinatorTests {

    // MARK: - nameComponents

    @Test("splits a full name into the two flat fields the RPC carries")
    func splitsFullName() {
        var components = PersonNameComponents()
        components.givenName = "Jane"
        components.familyName = "Doe"

        let name = AppleAuthCoordinator.nameComponents(from: components)
        #expect(name.first == "Jane")
        #expect(name.last == "Doe")
    }

    // Apple omits the name entirely on every authorization after the first,
    // which is the common case — it must degrade to empty, not crash.
    @Test("returns empty fields when Apple sends no name")
    func handlesMissingName() {
        let name = AppleAuthCoordinator.nameComponents(from: nil)
        #expect(name.first.isEmpty)
        #expect(name.last.isEmpty)
    }

    @Test("tolerates a partially populated name")
    func handlesPartialName() {
        var components = PersonNameComponents()
        components.givenName = "Prince"

        let name = AppleAuthCoordinator.nameComponents(from: components)
        #expect(name.first == "Prince")
        #expect(name.last.isEmpty)
    }

    // MARK: - string(from:)

    @Test("decodes Apple's Data-typed token fields as UTF-8")
    func decodesTokenData() {
        let token = "header.payload.signature"
        #expect(AppleAuthCoordinator.string(from: Data(token.utf8)) == token)
    }

    @Test("treats nil and empty token data as absent", arguments: [nil, Data()])
    func rejectsEmptyTokenData(data: Data?) {
        #expect(AppleAuthCoordinator.string(from: data) == nil)
    }

    // MARK: - errorMessage(for:)

    // The backend maps an unverifiable identity token to invalidArgument.
    @Test("maps invalidArgument to a verification-specific message")
    func mapsInvalidArgument() {
        let message = AppleAuthCoordinator.errorMessage(
            for: ConnectError(code: .invalidArgument, message: "invalid Apple identity token")
        )
        #expect(message == "Apple sign-in couldn't be verified. Please try again.")
    }

    @Test("maps permissionDenied to an account-state message")
    func mapsPermissionDenied() {
        let message = AppleAuthCoordinator.errorMessage(
            for: ConnectError(code: .permissionDenied, message: "account is inactive")
        )
        #expect(message == "This account can't sign in right now.")
    }

    @Test(
        "maps unavailable/deadlineExceeded to a connectivity message",
        arguments: [Code.unavailable, Code.deadlineExceeded]
    )
    func mapsConnectivityErrors(code: Code) {
        let message = AppleAuthCoordinator.errorMessage(for: ConnectError(code: code, message: nil))
        #expect(message == "Can't reach the server. Check your connection and try again.")
    }

    @Test("falls back to a generic message for unexpected codes")
    func mapsUnknownCode() {
        let message = AppleAuthCoordinator.errorMessage(for: ConnectError(code: .internalError, message: nil))
        #expect(message == AppleAuthCoordinator.genericErrorMessage())
    }
}
