import Foundation

/// Derives the wire-format day-of-month/day-of-week fields from the
/// user-picked anchor date. `FixedExpense.anchor_date` is the source of
/// truth the user actually edits; `day_of_month`/`day_of_week` are plain
/// (non-optional) int32 fields on the request messages with no way to say
/// "compute this yourself", so the client derives and sends both.
nonisolated enum FixedExpenseScheduling {
    static func dayOfMonth(for date: Date) -> Int32 {
        Int32(Calendar.current.component(.day, from: date))
    }

    /// ISO 8601: 1 = Monday ... 7 = Sunday. `Calendar`'s `.weekday` component
    /// is 1 = Sunday ... 7 = Saturday (Gregorian), so it needs remapping.
    static func dayOfWeek(for date: Date) -> Int32 {
        let weekday = Calendar.current.component(.weekday, from: date)
        return Int32((weekday + 5) % 7 + 1)
    }
}
