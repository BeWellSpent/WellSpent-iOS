import Foundation
import Testing
@testable import WellSpent

/// Exercises the real Simulator Keychain. Deliberately never calls `read()`
/// here — on an access-control-protected item that triggers a real system
/// Face ID/Touch ID/passcode prompt, which a unit test can't answer.
@Suite("KeychainRefreshTokenStore")
struct KeychainRefreshTokenStoreTests {
    private func makeStore() -> KeychainRefreshTokenStore {
        KeychainRefreshTokenStore(service: "com.bewellspent.WellSpent.tests.refresh.\(UUID().uuidString)")
    }

    @Test("exists is false before anything is saved")
    func existsFalseInitially() {
        let store = makeStore()
        #expect(!store.exists())
    }

    @Test("save makes exists true, with no read of the secret involved")
    func existsTrueAfterSaveWithNoPromptingRead() {
        let store = makeStore()
        store.save(token: "refresh-one", accessControl: .userPresence)
        #expect(store.exists())
    }

    @Test("save with biometryCurrentSet also succeeds, with no read of the secret involved")
    func existsTrueAfterSaveWithBiometryCurrentSet() {
        let store = makeStore()
        store.save(token: "refresh-biometric", accessControl: .biometryCurrentSet)
        #expect(store.exists())
    }

    @Test("saving again overwrites rather than failing, still with no read")
    func savingTwiceOverwrites() {
        let store = makeStore()
        store.save(token: "first", accessControl: .userPresence)
        store.save(token: "second", accessControl: .userPresence)
        #expect(store.exists())
    }

    @Test("clearing then saving under a different access control re-creates the item")
    func clearThenSaveWithDifferentAccessControlRecreatesItem() {
        let store = makeStore()
        store.save(token: "first", accessControl: .userPresence)
        store.clear()
        store.save(token: "second", accessControl: .biometryCurrentSet)
        #expect(store.exists())
    }

    @Test("clear removes the item")
    func clearRemovesItem() {
        let store = makeStore()
        store.save(token: "to-clear", accessControl: .userPresence)
        store.clear()
        #expect(!store.exists())
    }

    @Test("clearing when nothing is stored does not throw or crash")
    func clearWhenAbsentIsSafe() {
        let store = makeStore()
        store.clear()
        #expect(!store.exists())
    }
}
