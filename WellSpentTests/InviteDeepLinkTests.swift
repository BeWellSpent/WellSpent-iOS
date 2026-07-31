import Foundation
import Testing
@testable import WellSpent

@Suite("InviteDeepLink")
struct InviteDeepLinkTests {
    @Test("extracts the token from a locale-prefixed invite URL")
    func extractsTokenWithLocalePrefix() {
        let url = URL(string: "https://bewellspent.com/en/invite/abc123")!
        #expect(InviteDeepLink.token(from: url) == "abc123")
    }

    @Test("extracts the token regardless of locale")
    func extractsTokenWithDifferentLocale() {
        let url = URL(string: "https://bewellspent.com/es/invite/xyz789")!
        #expect(InviteDeepLink.token(from: url) == "xyz789")
    }

    @Test("extracts the token from a bare invite path")
    func extractsTokenFromBarePath() {
        let url = URL(string: "https://bewellspent.com/invite/abc123")!
        #expect(InviteDeepLink.token(from: url) == "abc123")
    }

    @Test("returns nil for unrelated paths")
    func returnsNilForUnrelatedPaths() {
        let url = URL(string: "https://bewellspent.com/en/login")!
        #expect(InviteDeepLink.token(from: url) == nil)
    }

    @Test("returns nil for the bare root path")
    func returnsNilForRootPath() {
        let url = URL(string: "https://bewellspent.com/")!
        #expect(InviteDeepLink.token(from: url) == nil)
    }
}
