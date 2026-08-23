import Foundation
import WellSpentAPI

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

    /// Payment-plan bidirectional math (mirrors web's `AddTransactionModal`/
    /// `EditFixedExpenseModal` `recalcEndDate`/`handleEndDateChange`): a
    /// number-of-payments field and an end-date field, each computed from
    /// the other given the expense's anchor date and interval. `intervalMonths`/
    /// `intervalWeeks` are clamped to a minimum of 1 — the stepper UIs never
    /// let them go to 0, but a defensive minimum avoids a division/multiply
    /// by zero if this is ever called with unvalidated input.
    static func endDate(fromTotalPayments totalPayments: Int, anchor: Date, frequencyUnit: Wellspent_V1_FrequencyUnit, intervalMonths: Int, intervalWeeks: Int) -> Date? {
        guard totalPayments > 0 else { return nil }
        let calendar = Calendar.current
        if frequencyUnit == .week {
            let days = (totalPayments - 1) * max(intervalWeeks, 1) * 7
            return calendar.date(byAdding: .day, value: days, to: anchor)
        } else {
            let months = (totalPayments - 1) * max(intervalMonths, 1)
            return calendar.date(byAdding: .month, value: months, to: anchor)
        }
    }

    static func totalPayments(fromEndDate endDate: Date, anchor: Date, frequencyUnit: Wellspent_V1_FrequencyUnit, intervalMonths: Int, intervalWeeks: Int) -> Int {
        max(1, intervalsElapsed(from: anchor, to: endDate, frequencyUnit: frequencyUnit, intervalMonths: intervalMonths, intervalWeeks: intervalWeeks) + 1)
    }

    private static func intervalsElapsed(from anchor: Date, to date: Date, frequencyUnit: Wellspent_V1_FrequencyUnit, intervalMonths: Int, intervalWeeks: Int) -> Int {
        let calendar = Calendar.current
        if frequencyUnit == .week {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: date)).day ?? 0
            let weeks = Int((Double(days) / 7.0).rounded())
            return weeks / max(intervalWeeks, 1)
        } else {
            let months = calendar.dateComponents([.month], from: anchor, to: date).month ?? 0
            return months / max(intervalMonths, 1)
        }
    }
}
