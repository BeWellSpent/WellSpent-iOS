import Foundation
import WellSpentAPI

/// The backend has no concept of "one job, several paydays" — a salary paid
/// out semi-monthly is just two `IncomeSource` rows with the same name/type/
/// person/frequency and different `anchorDate`s (the period calculator
/// merges across every source and picks whichever occurrence comes first).
/// This groups those rows back into one logical job for display/editing.
/// Only ever called with *current* rows (`effectiveTo == nil`, already true
/// of everything `listIncomeSources` returns).
nonisolated enum IncomeJobGrouping {
    struct Row {
        let source: Wellspent_V1_IncomeSource
        let schedule: BudgetRESTMapping.IncomeSchedule
    }

    struct Job: Identifiable {
        struct Key: Hashable {
            let name: String
            let budgetPersonID: Int64
            let incomeType: Wellspent_V1_IncomeType
            let paymentFrequency: Wellspent_V1_RecurringType
        }

        let key: Key
        /// Sorted by pay date ascending (nil-anchor rows sort first) — the
        /// stable order both display and `AddEditIncomeViewModel`'s edit
        /// reconciliation rely on.
        let rows: [Row]
        var id: Key { key }

        var payDateCount: Int { rows.count }
        var totalAmount: (units: Int64, nanos: Int32) {
            TransactionAmountFormatting.sum(rows.map { (units: $0.source.defaultAmount.units, nanos: $0.source.defaultAmount.nanos) })
        }
    }

    static func group(sources: [Wellspent_V1_IncomeSource], schedules: [Int64: BudgetRESTMapping.IncomeSchedule]) -> [Job] {
        var order: [Job.Key] = []
        var buckets: [Job.Key: [Row]] = [:]
        for source in sources {
            let key = Job.Key(
                name: source.name,
                budgetPersonID: source.budgetPersonID,
                incomeType: source.incomeType,
                paymentFrequency: source.paymentFrequency
            )
            let row = Row(source: source, schedule: schedules[source.id] ?? BudgetRESTMapping.IncomeSchedule(anchorDate: nil, earlyArrivalToleranceDays: 0))
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = [row]
            } else {
                buckets[key]!.append(row)
            }
        }
        return order.map { Job(key: $0, rows: sortedRows(buckets[$0] ?? [])) }
    }

    static func sortedRows(_ rows: [Row]) -> [Row] {
        rows.sorted { lhs, rhs in
            let l = lhs.schedule.anchorDate ?? .distantPast
            let r = rhs.schedule.anchorDate ?? .distantPast
            if l != r { return l < r }
            return lhs.source.id < rhs.source.id
        }
    }
}
