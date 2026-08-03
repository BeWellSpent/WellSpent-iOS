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

    /// Reconstructs a display-only `Date` for a legacy `FixedExpense` that
    /// has no explicit `anchor_date` (nullable — added in migration 000025,
    /// after `day_of_month`/`day_of_week` already existed as the real
    /// schedule). Used only to populate the edit form's date picker with
    /// something that actually reflects the stored schedule, instead of
    /// today's date — the caller compares its own `startDate` against this
    /// value to detect whether the user actually changed it before deciding
    /// whether to send `anchor_date` back to the server at all.
    static func displayDate(dayOfMonth: Int32, dayOfWeek: Int32, isWeekly: Bool, referenceDate: Date = Date()) -> Date {
        let calendar = Calendar.current
        if isWeekly {
            // Reverse of dayOfWeek(for:)'s ISO remap: cal = (iso % 7) + 1.
            let calendarWeekday = (Int(dayOfWeek) % 7) + 1
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            components.weekday = calendarWeekday
            return calendar.date(from: components) ?? referenceDate
        } else {
            var components = calendar.dateComponents([.year, .month], from: referenceDate)
            let daysInMonth = calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 28
            components.day = min(max(1, Int(dayOfMonth)), daysInMonth)
            return calendar.date(from: components) ?? referenceDate
        }
    }
}
