import Testing
@testable import WellSpent

@Suite("ThresholdScope")
struct ThresholdScopeTests {
    @Test("raw values match the documented wire strings", arguments: [
        (ThresholdScope.budget, "budget"),
        (ThresholdScope.category, "category"),
    ])
    func rawValuesMatchWireStrings(_ pair: (ThresholdScope, String)) {
        #expect(pair.0.rawValue == pair.1)
    }

    @Test("every case has a non-empty label")
    func everyCaseHasLabel() {
        for scope in ThresholdScope.allCases {
            #expect(!scope.label.isEmpty)
        }
    }
}
