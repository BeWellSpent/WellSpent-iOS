import Testing
import Foundation
@testable import WellSpent

@Suite("IncomePayDateInput")
struct IncomePayDateInputTests {
    /// Same noon-anchored construction `FixedExpenseSchedulingTests` uses —
    /// stable regardless of the test runner's timezone.
    private func localDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    // MARK: - Monthly

    @Test("monthly construction preserves a valid day-of-month")
    func monthlyDatePreservesDay() {
        let reference = localDate(year: 2026, month: 3, day: 1)
        let result = IncomePayDateInput.monthlyDate(dayOfMonth: 15, referenceDate: reference)
        #expect(IncomePayDateInput.dayOfMonth(from: result) == 15)
        #expect(Calendar.current.component(.month, from: result) == 3)
        #expect(Calendar.current.component(.year, from: result) == 2026)
    }

    @Test("monthly construction preserves day 31 as a sentinel even when picked in a shorter month")
    func monthlyDatePreservesDay31Sentinel() {
        // April has only 30 days — day 31 ("Last day of month") must not
        // collapse into a literal 30 just because it was picked here. Only
        // `.day` is ever read back for a monthly anchor, so the backend
        // re-clamps per actual target month on every occurrence anyway.
        let reference = localDate(year: 2026, month: 4, day: 1)
        let result = IncomePayDateInput.monthlyDate(dayOfMonth: 31, referenceDate: reference)
        #expect(IncomePayDateInput.dayOfMonth(from: result) == 31)
    }

    @Test("monthly construction still clamps a literal (non-31) day to the reference month's real length")
    func monthlyDateStillClampsOtherDays() {
        // April has 30 days.
        let reference = localDate(year: 2026, month: 4, day: 1)
        let result = IncomePayDateInput.monthlyDate(dayOfMonth: 30, referenceDate: reference)
        #expect(IncomePayDateInput.dayOfMonth(from: result) == 30)
        #expect(Calendar.current.component(.month, from: result) == 4)
    }

    @Test("monthly round trip returns the original day for every day that fits in the reference month")
    func monthlyRoundTrip() {
        let reference = localDate(year: 2026, month: 1, day: 1) // January has 31 days.
        for day in 1...31 {
            let result = IncomePayDateInput.monthlyDate(dayOfMonth: day, referenceDate: reference)
            #expect(IncomePayDateInput.dayOfMonth(from: result) == day)
        }
    }

    // MARK: - Yearly

    @Test("yearly construction preserves the picked month and day")
    func yearlyDatePreservesMonthAndDay() {
        let reference = localDate(year: 2026, month: 1, day: 1)
        let result = IncomePayDateInput.yearlyDate(month: 6, dayOfMonth: 20, referenceDate: reference)
        #expect(IncomePayDateInput.month(from: result) == 6)
        #expect(IncomePayDateInput.dayOfMonth(from: result) == 20)
        #expect(Calendar.current.component(.year, from: result) == 2026)
    }

    @Test("yearly construction clamps day 30 in February of a non-leap year")
    func yearlyDateClampsFebruary() {
        let reference = localDate(year: 2026, month: 1, day: 1) // 2026 is not a leap year.
        let result = IncomePayDateInput.yearlyDate(month: 2, dayOfMonth: 30, referenceDate: reference)
        #expect(IncomePayDateInput.month(from: result) == 2)
        #expect(IncomePayDateInput.dayOfMonth(from: result) == 28)
    }

    @Test("yearly round trip returns the original month and day")
    func yearlyRoundTrip() {
        let reference = localDate(year: 2026, month: 1, day: 1)
        for month in 1...12 {
            let result = IncomePayDateInput.yearlyDate(month: month, dayOfMonth: 10, referenceDate: reference)
            #expect(IncomePayDateInput.month(from: result) == month)
            #expect(IncomePayDateInput.dayOfMonth(from: result) == 10)
        }
    }

    // MARK: - Weekly / bi-weekly

    @Test("weekday construction never produces a future date")
    func weekdayConstructionNeverFuture() {
        // 2026-03-18 is a Wednesday (ISO 3).
        let reference = localDate(year: 2026, month: 3, day: 18)
        for isoWeekday in 1...7 {
            let result = IncomePayDateInput.weekdayDate(isoWeekday: isoWeekday, referenceDate: reference)
            #expect(result <= reference)
        }
    }

    @Test("weekday construction picking today's own weekday returns today")
    func weekdayConstructionSameDay() {
        // 2026-03-18 is a Wednesday (ISO 3).
        let reference = localDate(year: 2026, month: 3, day: 18)
        let result = IncomePayDateInput.weekdayDate(isoWeekday: 3, referenceDate: reference)
        #expect(Calendar.current.isDate(result, inSameDayAs: reference))
    }

    @Test("weekday construction picking a later weekday rolls back to the previous week")
    func weekdayConstructionRollsBack() {
        // 2026-03-18 is a Wednesday (ISO 3); Friday (ISO 5) most recently
        // fell on 2026-03-13.
        let reference = localDate(year: 2026, month: 3, day: 18)
        let result = IncomePayDateInput.weekdayDate(isoWeekday: 5, referenceDate: reference)
        let expected = localDate(year: 2026, month: 3, day: 13)
        #expect(Calendar.current.isDate(result, inSameDayAs: expected))
    }

    @Test("weekday round trip returns the original ISO weekday")
    func weekdayRoundTrip() {
        let reference = localDate(year: 2026, month: 3, day: 18)
        for isoWeekday in 1...7 {
            let result = IncomePayDateInput.weekdayDate(isoWeekday: isoWeekday, referenceDate: reference)
            #expect(IncomePayDateInput.isoWeekday(from: result) == isoWeekday)
        }
    }
}
