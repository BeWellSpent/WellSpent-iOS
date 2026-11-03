import Foundation
import WellSpentAPI

/// Detects a transaction counted into a period before that period's own
/// start date. The only way this happens is the early-arrival-tolerance
/// mechanism (issue #101): an income deposit that arrives up to
/// `early_arrival_tolerance_days` before its scheduled anchor is still
/// assigned to the period that anchor defines, rather than the period its
/// deposit date would otherwise fall in. No new backend field needed — the
/// signal is purely `transaction.date < period.startDate` for whichever
/// period the transaction is actually assigned to. See
/// docs/features/income-defined-budget-periods.md.
nonisolated enum IncomeArrivalTiming {
    static func arrivedEarly(_ transaction: Wellspent_V1_Transaction, periodStartDate: Date) -> Bool {
        transaction.date.dateOnly < periodStartDate
    }
}
