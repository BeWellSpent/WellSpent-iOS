import SwiftUI
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AllocateCategoryViewModel")
@MainActor
struct AllocateCategoryViewModelTests {
    private let category = Wellspent_V1_Category.with { $0.id = 7; $0.name = "Groceries" }
    private let alex = Wellspent_V1_BudgetPerson.with { $0.id = 1; $0.userName = "Alex" }
    private let sam = Wellspent_V1_BudgetPerson.with { $0.id = 2; $0.userName = "Sam" }

    @Test("pre-fills from an existing allocation and leaves people without one blank")
    func prefillsFromExistingAllocations() {
        let existing = Wellspent_V1_ExpenseAllocation.with {
            $0.id = 42
            $0.categoryID = 7
            $0.budgetPersonID = 1
            $0.plannedAmount = .with { $0.units = 200; $0.currency = "USD" }
        }
        let viewModel = AllocateCategoryViewModel(category: category, people: [alex, sam], existingAllocations: [existing])

        #expect(viewModel.rows.first { $0.id == 1 }?.amountText == "200")
        #expect(viewModel.rows.first { $0.id == 2 }?.amountText == "")
    }

    @Test("a nonblank valid amount becomes an upsert")
    func nonblankAmountBecomesUpsert() {
        let viewModel = AllocateCategoryViewModel(category: category, people: [alex], existingAllocations: [])
        viewModel.amountText(for: 1).wrappedValue = "150"

        let changes = viewModel.computeChanges(currencyCode: "USD")
        #expect(changes.upserted.count == 1)
        #expect(changes.upserted.first?.budgetPersonID == 1)
        #expect(changes.upserted.first?.categoryID == 7)
        #expect(changes.upserted.first?.plannedAmount.units == 150)
        #expect(changes.deletedIDs.isEmpty)
    }

    @Test("clearing a row that had an existing allocation becomes a delete")
    func clearingExistingRowBecomesDelete() {
        let existing = Wellspent_V1_ExpenseAllocation.with {
            $0.id = 42
            $0.categoryID = 7
            $0.budgetPersonID = 1
            $0.plannedAmount = .with { $0.units = 200; $0.currency = "USD" }
        }
        let viewModel = AllocateCategoryViewModel(category: category, people: [alex], existingAllocations: [existing])
        viewModel.amountText(for: 1).wrappedValue = ""

        let changes = viewModel.computeChanges(currencyCode: "USD")
        #expect(changes.deletedIDs == [42])
        #expect(changes.upserted.isEmpty)
    }

    @Test("a blank row with no prior allocation produces neither an upsert nor a delete")
    func blankRowWithNoPriorAllocationIsSkipped() {
        let viewModel = AllocateCategoryViewModel(category: category, people: [alex], existingAllocations: [])

        let changes = viewModel.computeChanges(currencyCode: "USD")
        #expect(changes.upserted.isEmpty)
        #expect(changes.deletedIDs.isEmpty)
    }

    @Test("canSubmit is false while any row has invalid non-blank input")
    func canSubmitReflectsInvalidInput() {
        let viewModel = AllocateCategoryViewModel(category: category, people: [alex], existingAllocations: [])
        #expect(viewModel.canSubmit)

        viewModel.amountText(for: 1).wrappedValue = "not a number"
        #expect(!viewModel.canSubmit)

        viewModel.amountText(for: 1).wrappedValue = "42.50"
        #expect(viewModel.canSubmit)
    }
}
