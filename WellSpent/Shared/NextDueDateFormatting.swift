import Foundation
import WellSpentAPI

/// Formats a "next due" date for display.
///
/// Shared by the Fixed tab's Future rows and the Expense Plan tab's upcoming
/// bills, which show the same fact about the same templates and would
/// otherwise format it two different ways.
///
/// Reads through `dateOnly`, never the raw timestamp: the backend encodes
/// these as midnight UTC, so interpreting one in a timezone behind UTC lands
/// a day early (see `Shared/DateOnly.swift`, and the v1.15.1 bug class).
nonisolated enum NextDueDateFormatting {
    /// Empty when the backend didn't supply a date, so a caller can treat
    /// "no date" and "nothing to show" identically.
    static func text(_ timestamp: Google_Protobuf_Timestamp?, localeIdentifier: String) -> String {
        guard let timestamp else { return "" }
        return timestamp.dateOnly.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(Locale(identifier: localeIdentifier))
        )
    }
}
