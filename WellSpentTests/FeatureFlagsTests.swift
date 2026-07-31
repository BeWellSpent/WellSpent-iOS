import Testing
@testable import WellSpent

@Suite("FeatureFlags")
struct FeatureFlagsTests {
    @Test("recognizes common truthy values", arguments: ["1", "true", "TRUE", "yes", "Yes"])
    func recognizesTruthyValues(value: String) {
        #expect(FeatureFlags.isEnabled("KEY", in: ["KEY": value]))
    }

    @Test("treats falsy or unrecognized values as disabled", arguments: ["0", "false", "no", "garbage", ""])
    func treatsOtherValuesAsDisabled(value: String) {
        #expect(!FeatureFlags.isEnabled("KEY", in: ["KEY": value]))
    }

    @Test("an unset key is disabled")
    func unsetKeyIsDisabled() {
        #expect(!FeatureFlags.isEnabled("MISSING_KEY", in: [:]))
    }
}
