import Foundation
import WellSpentAPI

/// How Plan's Fixed expenses list groups its templates. Due-this-period comes
/// from the server (`dueFixedExpenseIDs`), never re-derived from schedules.
nonisolated enum PlanFixedGrouping {
    struct Groups: Equatable {
        /// Installments and payment plans, ending soonest first.
        var plans: [Wellspent_V1_FixedExpense]
        /// Open-ended bills due this period.
        var recurring: [Wellspent_V1_FixedExpense]
        /// Open-ended bills not due this period.
        var notDue: [Wellspent_V1_FixedExpense]
    }

    /// `dueIDs` nil (an older server) puts every open-ended bill in `recurring`
    /// rather than guessing which ones are due.
    static func group(_ templates: [Wellspent_V1_FixedExpense], dueIDs: Set<String>?) -> Groups {
        var groups = Groups(plans: [], recurring: [], notDue: [])
        for template in templates {
            if FixedExpensePlanSummary.kind(for: template) != nil {
                groups.plans.append(template)
            } else if let dueIDs, !dueIDs.contains(template.id) {
                groups.notDue.append(template)
            } else {
                groups.recurring.append(template)
            }
        }
        groups.plans.sort { endKey($0) < endKey($1) }
        return groups
    }

    /// Templates due this period, for the summary card's bill count.
    static func dueCount(_ templates: [Wellspent_V1_FixedExpense], dueIDs: Set<String>?) -> Int? {
        guard let dueIDs else { return nil }
        return templates.filter { dueIDs.contains($0.id) }.count
    }

    /// A plan with no end date sorts after every dated one.
    private static func endKey(_ template: Wellspent_V1_FixedExpense) -> Date {
        template.hasEndDate ? template.endDate.dateOnly : .distantFuture
    }
}
