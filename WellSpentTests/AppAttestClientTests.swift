import Foundation
import Testing
@testable import WellSpent

@Suite("AppAttestClient")
struct AppAttestClientTests {
    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    @Test("client data hash matches the backend: SHA-256 of action|email|challenge, email trimmed and lowercased")
    func clientDataHashMatchesBackend() {
        let hash = AppAttestClient.clientDataHash(action: "login", email: "  A@B.com ", challenge: "ch")
        #expect(hex(hash) == "1ee8aedb3f352d082779ed4ec127e6b66a1f16ecda0507d853015de61deec0d8")
    }

    @Test("a different action signs different bytes")
    func actionIsBound() {
        #expect(AppAttestClient.clientDataHash(action: "login", email: "a@b.com", challenge: "ch")
            != AppAttestClient.clientDataHash(action: "register", email: "a@b.com", challenge: "ch"))
    }
}
