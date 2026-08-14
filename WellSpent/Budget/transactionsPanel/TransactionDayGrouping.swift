import Foundation
import WellSpentAPI

/// Buckets transactions by calendar day for the sticky-header day-grouped
/// list. Mirrors web's day-grouping (`transactionsPanel/helpers.ts`,
/// `groupTransactionsByDay`) but truncates to an explicit day boundary via
/// `Calendar.startOfDay(for:)` rather than reusing the raw timestamp —
/// web's grouping key only works because the backend's `date` field happens
/// to already be day-granularity; truncating explicitly here is more robust.
nonisolated enum TransactionDayGrouping {
    struct DayGroup: Identifiable {
        let id: Date
        let transactions: [Wellspent_V1_Transaction]
    }

    /// Preserves the incoming relative order within each day (callers pass an
    /// already-sorted array). Day buckets default to newest-first, matching
    /// the Variable list, which reads as a feed. The Fixed list passes
    /// `ascending: true` — it reads as a schedule, so the month should run
    /// top to bottom. Callers must sort their input the same way, since the
    /// order inside a day is taken as given.
    static func group(_ transactions: [Wellspent_V1_Transaction], ascending: Bool = false) -> [DayGroup] {
        var buckets: [Date: [Wellspent_V1_Transaction]] = [:]
        let calendar = Calendar.current

        for transaction in transactions {
            // `transaction.date` is a DATE-only field (see `DateOnly.swift`)
            // — `.dateOnly`, not `.date`, or the day boundary is wrong for
            // any timezone behind UTC.
            let day = calendar.startOfDay(for: transaction.date.dateOnly)
            buckets[day, default: []].append(transaction)
        }

        return buckets.keys
            .sorted(by: ascending ? (<) : (>))
            .map { DayGroup(id: $0, transactions: buckets[$0] ?? []) }
    }

    static func headerText(for date: Date, localeIdentifier: String) -> String {
        date.formatted(
            Date.FormatStyle(locale: Locale(identifier: localeIdentifier))
                .weekday(.wide)
                .month(.wide)
                .day()
        )
    }
}
