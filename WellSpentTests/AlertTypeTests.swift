import Testing
@testable import WellSpent

@Suite("AlertType")
struct AlertTypeTests {
    @Test("raw values match the documented wire strings", arguments: [
        (AlertType.newTransaction, "new_transaction"),
        (AlertType.spendingThreshold, "spending_threshold"),
        (AlertType.periodCreated, "period_created"),
        (AlertType.reviewPending, "review_pending"),
    ])
    func rawValuesMatchWireStrings(_ pair: (AlertType, String)) {
        #expect(pair.0.rawValue == pair.1)
    }

    @Test("every case has a non-empty label and explanation")
    func everyCaseHasLabelAndExplanation() {
        for type in AlertType.all {
            #expect(!type.label.isEmpty)
            #expect(!type.explanation.isEmpty)
        }
    }

    @Test("all contains exactly the four documented types")
    func allContainsFourTypes() {
        #expect(AlertType.all.count == 4)
        #expect(Set(AlertType.all) == Set(AlertType.allCases))
    }
}
