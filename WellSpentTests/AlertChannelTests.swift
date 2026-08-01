import Testing
@testable import WellSpent

@Suite("AlertChannel")
struct AlertChannelTests {
    @Test("raw values match the documented wire strings", arguments: [
        (AlertChannel.inApp, "in_app"),
        (AlertChannel.email, "email"),
        (AlertChannel.both, "both"),
    ])
    func rawValuesMatchWireStrings(_ pair: (AlertChannel, String)) {
        #expect(pair.0.rawValue == pair.1)
    }

    @Test("every case has a non-empty label")
    func everyCaseHasLabel() {
        for channel in AlertChannel.allCases {
            #expect(!channel.label.isEmpty)
        }
    }
}
