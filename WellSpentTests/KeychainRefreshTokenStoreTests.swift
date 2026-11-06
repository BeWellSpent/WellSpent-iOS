import Foundation
import Security
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

    @Test("only a missing item reads as notFound; every other failure is unavailable, never a reason to delete")
    func readResultMapsStatuses() {
        let data = Data("tok".utf8)
        #expect(KeychainRefreshTokenStore.readResult(status: errSecSuccess, data: data) == .token("tok"))
        #expect(KeychainRefreshTokenStore.readResult(status: errSecItemNotFound, data: nil) == .notFound)
        #expect(KeychainRefreshTokenStore.readResult(status: errSecUserCanceled, data: nil) == .unavailable)
        #expect(KeychainRefreshTokenStore.readResult(status: errSecAuthFailed, data: nil) == .unavailable)
        #expect(KeychainRefreshTokenStore.readResult(status: errSecInteractionNotAllowed, data: nil) == .unavailable)
    }

    @Test("a rotated token that can't be written in place is replaced, so the Keychain never keeps a revoked one")
    func failedUpdateIsReplaced() {
        #expect(!KeychainRefreshTokenStore.shouldReplaceItem(afterUpdate: errSecSuccess))
        #expect(!KeychainRefreshTokenStore.shouldReplaceItem(afterUpdate: errSecItemNotFound)) // the add path handles this
        #expect(KeychainRefreshTokenStore.shouldReplaceItem(afterUpdate: errSecUserCanceled))
        #expect(KeychainRefreshTokenStore.shouldReplaceItem(afterUpdate: errSecAuthFailed))
        #expect(KeychainRefreshTokenStore.shouldReplaceItem(afterUpdate: errSecInteractionNotAllowed))
    }
}
