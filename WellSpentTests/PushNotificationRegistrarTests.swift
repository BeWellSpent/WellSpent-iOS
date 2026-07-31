import Foundation
import Testing
@testable import WellSpent

@Suite("PushNotificationRegistrar")
struct PushNotificationRegistrarTests {
    @Test("converts raw device token bytes to a lowercase hex string")
    func hexStringMatchesExpectedEncoding() {
        let data = Data([0x00, 0x0F, 0xA1, 0xFF])
        #expect(PushNotificationRegistrar.hexString(from: data) == "000fa1ff")
    }

    @Test("empty data produces an empty string")
    func emptyDataProducesEmptyString() {
        #expect(PushNotificationRegistrar.hexString(from: Data()).isEmpty)
    }
}
