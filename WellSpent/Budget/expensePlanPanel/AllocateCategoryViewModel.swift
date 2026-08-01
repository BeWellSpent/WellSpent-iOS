import Foundation
import Observation
import SwiftUI
import WellSpentAPI

/// One row per budget person for a single category. No network call of its
/// own — `submit()` computes the upsert/delete diff against what was loaded
/// and hands it back to `ExpensePlanViewModel.applyAllocationChanges`, same
/// "sheet computes, parent view model calls the RPC" split as `MarkAsPaidView`.
@MainActor
@Observable
final class AllocateCategoryViewModel {
    struct PersonRow: Identifiable {
        let person: Wellspent_V1_BudgetPerson
        var amountText: String
        let existingAllocationID: Int64?

        var id: Int64 { person.id }
    }

    let category: Wellspent_V1_Category
    var rows: [PersonRow]

    init(category: Wellspent_V1_Category, people: [Wellspent_V1_BudgetPerson], existingAllocations: [Wellspent_V1_ExpenseAllocation]) {
        self.category = category
        self.rows = people.map { person in
            let existing = existingAllocations.first { $0.budgetPersonID == person.id }
            return PersonRow(
                person: person,
                amountText: existing.map { MoneyInput.formatForEditing(units: $0.plannedAmount.units, nanos: $0.plannedAmount.nanos) } ?? "",
                existingAllocationID: existing?.id
            )
        }
    }

    var canSubmit: Bool {
        rows.allSatisfy { row in
            row.amountText.trimmingCharacters(in: .whitespaces).isEmpty || MoneyInput.parseAmount(row.amountText) != nil
        }
    }

    func amountText(for personID: Int64) -> Binding<String> {
        Binding(
            get: { self.rows.first { $0.id == personID }?.amountText ?? "" },
            set: { newValue in
                if let index = self.rows.firstIndex(where: { $0.id == personID }) {
                    self.rows[index].amountText = newValue
                }
            }
        )
    }

    /// Splits rows into `(upserted, deletedIDs)`: a nonblank row with a valid
    /// amount becomes an upsert; a row that had an existing allocation but is
    /// now blank becomes a delete. A row left blank that never had an
    /// allocation is skipped entirely.
    func computeChanges(currencyCode: String) -> (
        upserted: [(budgetPersonID: Int64, categoryID: Int32, plannedAmount: Wellspent_V1_Money)],
        deletedIDs: [Int64]
    ) {
        var upserted: [(budgetPersonID: Int64, categoryID: Int32, plannedAmount: Wellspent_V1_Money)] = []
        var deletedIDs: [Int64] = []

        for row in rows {
            let trimmed = row.amountText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if let existingID = row.existingAllocationID {
                    deletedIDs.append(existingID)
                }
                continue
            }

            guard let parsed = MoneyInput.parseAmount(row.amountText) else { continue }
            let money = Wellspent_V1_Money.with {
                $0.units = parsed.units
                $0.nanos = parsed.nanos
                $0.currency = currencyCode
            }
            upserted.append((budgetPersonID: row.person.id, categoryID: category.id, plannedAmount: money))
        }

        return (upserted, deletedIDs)
    }
}
