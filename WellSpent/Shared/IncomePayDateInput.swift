import Foundation

/// Construction/extraction between a simplified pay-schedule picker
/// (day-of-month / month+day / ISO weekday — never a year or an exact
/// historical month) and the real `Date` `AddEditIncomeViewModel.payDates`
/// stores. Monthly/yearly reuse `FixedExpenseScheduling.displayDate`'s
/// day-in-month clamping rather than re-deriving it.
nonisolated enum IncomePayDateInput {
    /// Current year/month — except day 31 ("Last day of month"), which is
    /// preserved literally via a 31-day scaffold month instead of clamping
    /// to whichever month happens to be on screen. The backend's
    /// `NextMonthly` discards a monthly anchor's own month/year entirely and
    /// only ever reads `.Day`, so collapsing 31 down to e.g. 30 just because
    /// it was picked in November would permanently lose the "always the
    /// last day" meaning — the stored day would stay 30 forever, skipping
    /// the 31st in every 31-day month from then on.
    static func monthlyDate(dayOfMonth: Int, referenceDate: Date = Date()) -> Date {
        guard dayOfMonth == 31 else {
            return FixedExpenseScheduling.displayDate(dayOfMonth: Int32(dayOfMonth), dayOfWeek: 1, isWeekly: false, referenceDate: referenceDate)
        }
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year], from: referenceDate)
        components.month = 1 // January always has 31 days; only `.day` is ever read back for a monthly anchor.
        components.day = 31
        return calendar.date(from: components) ?? referenceDate
    }

    static func dayOfMonth(from date: Date) -> Int {
        Int(FixedExpenseScheduling.dayOfMonth(for: date))
    }

    /// Current year, the picked month, clamped to that month's real length.
    /// Deliberately does NOT route through `monthlyDate`'s day-31 scaffold:
    /// `NextYearly` reads the anchor's month *and* day, so day 31 can't be
    /// preserved as a universal sentinel the way it can for monthly — day 31
    /// paired with February isn't even a representable calendar date, let
    /// alone one the backend's `DateOnly` could store. Every month except
    /// February has a constant length every year, so clamping here is exact
    /// and stable for all of them; February (28 vs. 29 by leap year) is the
    /// one case this can't express without a schema change, same as before.
    static func yearlyDate(month: Int, dayOfMonth: Int, referenceDate: Date = Date()) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year], from: referenceDate)
        components.month = month
        components.day = 1
        let monthReference = calendar.date(from: components) ?? referenceDate
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthReference)?.count ?? 28
        components.day = min(max(1, dayOfMonth), daysInMonth)
        return calendar.date(from: components) ?? monthReference
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
