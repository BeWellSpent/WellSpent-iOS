import Foundation

/// Construction/extraction between a simplified pay-schedule picker
/// (day-of-month / month+day / ISO weekday — never a year or an exact
/// historical month) and the real `Date` `AddEditIncomeViewModel.payDates`
/// stores. Monthly/yearly reuse `FixedExpenseScheduling.displayDate`'s
/// day-in-month clamping rather than re-deriving it.
nonisolated enum IncomePayDateInput {
    /// Current year/month, clamped to that month's real length.
    static func monthlyDate(dayOfMonth: Int, referenceDate: Date = Date()) -> Date {
        FixedExpenseScheduling.displayDate(dayOfMonth: Int32(dayOfMonth), dayOfWeek: 1, isWeekly: false, referenceDate: referenceDate)
    }

    static func dayOfMonth(from date: Date) -> Int {
        Int(FixedExpenseScheduling.dayOfMonth(for: date))
    }

    /// Current year, the picked month, clamped to that month's real length.
    static func yearlyDate(month: Int, dayOfMonth: Int, referenceDate: Date = Date()) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year], from: referenceDate)
        components.month = month
        components.day = 1
        let monthReference = calendar.date(from: components) ?? referenceDate
        return monthlyDate(dayOfMonth: dayOfMonth, referenceDate: monthReference)
    }

    static func month(from date: Date) -> Int {
        Calendar.current.component(.month, from: date)
    }

    /// Most recent occurrence of `isoWeekday` (1=Monday...7=Sunday) on or
    /// before `referenceDate` — never a future date, no past reference the
    /// user has to pick themselves.
    static func weekdayDate(isoWeekday: Int, referenceDate: Date = Date()) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let todayISO = Int(FixedExpenseScheduling.dayOfWeek(for: today))
        let diff = (todayISO - isoWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -diff, to: today) ?? today
    }

    static func isoWeekday(from date: Date) -> Int {
        Int(FixedExpenseScheduling.dayOfWeek(for: date))
    }
}
