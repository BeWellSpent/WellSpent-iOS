import Foundation
import Testing
@testable import WellSpent

@Suite("AuthDeviceIDStore")
struct AuthDeviceIDStoreTests {
    private func makeStore() -> AuthDeviceIDStore {
        AuthDeviceIDStore(service: "com.bewellspent.WellSpent.tests.deviceID.\(UUID().uuidString)")
    }

    @Test("generates and persists an ID on first read")
    func generatesOnFirstRead() {
        let store = makeStore()
        let id = store.deviceID()
        #expect(!id.isEmpty)
    }

    @Test("repeated reads return the same ID, not a fresh one each time")
    func stableAcrossReads() {
        let store = makeStore()
        let first = store.deviceID()
        let second = store.deviceID()
        #expect(first == second)
    }

    @Test("clearing then reading again generates a different ID")
    func regeneratesAfterClear() {
        let store = makeStore()
        let first = store.deviceID()
        store.clear()
        let second = store.deviceID()
        #expect(first != second)
    }
}
