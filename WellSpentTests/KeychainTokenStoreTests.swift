import Foundation
import Testing
@testable import WellSpent

/// Exercises the real Simulator Keychain (works fine under `xcodebuild test`).
/// Each test uses a unique service name so tests can't interfere with each
/// other or with anything the running app itself might have stored.
@Suite("KeychainTokenStore")
struct KeychainTokenStoreTests {
    private func makeStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "com.bewellspent.WellSpent.tests.\(UUID().uuidString)")
    }

    @Test("reading before anything is saved returns nil, not an error")
    func readBeforeSaveReturnsNil() {
        let store = makeStore()
        #expect(store.readToken() == nil)
    }

    @Test("save then read round-trips the same token")
    func saveThenReadRoundTrips() {
        let store = makeStore()
        store.save(token: "token-one")
        #expect(store.readToken() == "token-one")
    }

    @Test("saving again overwrites the previous token rather than failing")
    func savingTwiceOverwrites() {
        let store = makeStore()
        store.save(token: "first")
        store.save(token: "second")
        #expect(store.readToken() == "second")
    }

    @Test("delete removes the token")
    func deleteRemovesToken() {
        let store = makeStore()
        store.save(token: "to-delete")
        store.deleteToken()
        #expect(store.readToken() == nil)
    }

    @Test("deleting when nothing is stored does not throw or crash")
    func deleteWhenAbsentIsSafe() {
        let store = makeStore()
        store.deleteToken()
        #expect(store.readToken() == nil)
    }
}
