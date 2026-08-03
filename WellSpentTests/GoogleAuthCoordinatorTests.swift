import Foundation
import Testing
@testable import WellSpent

@Suite("GoogleAuthCoordinator")
struct GoogleAuthCoordinatorTests {
    @Test("extracts the code when state matches")
    func extractsCodeOnMatch() {
        let url = URL(string: "https://bewellspent.com/auth/callback?code=abc123&state=xyz")!
        let result = GoogleAuthCoordinator.extractCode(from: url, expectedState: "xyz")
        #expect(result == .success("abc123"))
    }

    @Test("fails when no code is present")
    func failsWithoutCode() {
        let url = URL(string: "https://bewellspent.com/auth/callback?state=xyz")!
        let result = GoogleAuthCoordinator.extractCode(from: url, expectedState: "xyz")
        #expect(result == .failure("No authorization code received from Google."))
    }

    @Test("fails when state doesn't match")
    func failsOnStateMismatch() {
        let url = URL(string: "https://bewellspent.com/auth/callback?code=abc123&state=wrong")!
        let result = GoogleAuthCoordinator.extractCode(from: url, expectedState: "xyz")
        #expect(result == .failure("Invalid state parameter. Please try again."))
    }

    @Test("fails when state is entirely missing")
    func failsOnMissingState() {
        let url = URL(string: "https://bewellspent.com/auth/callback?code=abc123")!
        let result = GoogleAuthCoordinator.extractCode(from: url, expectedState: "xyz")
        #expect(result == .failure("Invalid state parameter. Please try again."))
    }
}
