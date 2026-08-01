import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PersonReplacement")
struct PersonReplacementTests {
    private func person(id: Int64) -> Wellspent_V1_BudgetPerson {
        .with {
            $0.id = id
            $0.userName = "Person \(id)"
        }
    }

    private func incomeSource(budgetPersonID: Int64) -> Wellspent_V1_IncomeSource {
        .with { $0.budgetPersonID = budgetPersonID }
    }

    @Test("no income sources means no replacement is needed")
    func noIncomeSources() {
        #expect(!PersonReplacement.needsReplacement(person: person(id: 1), incomeSources: []))
    }

    @Test("an income source attributed to the person requires a replacement")
    func attributedIncomeSource() {
        let sources = [incomeSource(budgetPersonID: 1)]
        #expect(PersonReplacement.needsReplacement(person: person(id: 1), incomeSources: sources))
    }

    @Test("income sources attributed to other people, or unattributed, don't require a replacement")
    func unrelatedIncomeSources() {
        let sources = [incomeSource(budgetPersonID: 2), incomeSource(budgetPersonID: 0)]
        #expect(!PersonReplacement.needsReplacement(person: person(id: 1), incomeSources: sources))
    }
}
