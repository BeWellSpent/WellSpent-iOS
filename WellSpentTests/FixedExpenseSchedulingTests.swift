import Testing
import Foundation
import WellSpentAPI
@testable import WellSpent

@Suite("FixedExpenseScheduling")
struct FixedExpenseSchedulingTests {
    /// Builds the date via `Calendar.current` (matching the calendar
    /// `FixedExpenseScheduling` itself uses) at noon, so the assertion is
    /// stable regardless of the test runner's timezone — a midnight
    /// timestamp could shift to the previous/next calendar day once
    /// re-interpreted in a different offset.
    private func localDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    @Test("derives day of month directly from the date")
    func dayOfMonth() {
        #expect(FixedExpenseScheduling.dayOfMonth(for: localDate(year: 2026, month: 3, day: 15)) == 15)
        #expect(FixedExpenseScheduling.dayOfMonth(for: localDate(year: 2026, month: 1, day: 31)) == 31)
    }

    @Test("derives ISO 8601 day of week (1=Monday...7=Sunday)")
    func dayOfWeek() {
        // 2026-03-16 is a Monday.
        #expect(FixedExpenseScheduling.dayOfWeek(for: localDate(year: 2026, month: 3, day: 16)) == 1)
        // 2026-03-22 is a Sunday.
        #expect(FixedExpenseScheduling.dayOfWeek(for: localDate(year: 2026, month: 3, day: 22)) == 7)
        // 2026-03-20 is a Friday.
        #expect(FixedExpenseScheduling.dayOfWeek(for: localDate(year: 2026, month: 3, day: 20)) == 5)
    }

    @Test("displayDate reconstructs the stored day-of-month within the reference month")
    func displayDatePreservesDayOfMonth() {
        let reference = localDate(year: 2026, month: 3, day: 16)
        let result = FixedExpenseScheduling.displayDate(dayOfMonth: 5, dayOfWeek: 0, isWeekly: false, referenceDate: reference)
        #expect(Calendar.current.component(.day, from: result) == 5)
        #expect(Calendar.current.component(.month, from: result) == 3)
        #expect(Calendar.current.component(.year, from: result) == 2026)
    }

    @Test("displayDate clamps day-of-month to the reference month's last day")
    func displayDateClampsToShorterMonth() {
        // April has 30 days — a day_of_month of 31 (valid in e.g. January) must clamp.
        let reference = localDate(year: 2026, month: 4, day: 10)
        let result = FixedExpenseScheduling.displayDate(dayOfMonth: 31, dayOfWeek: 0, isWeekly: false, referenceDate: reference)
        #expect(Calendar.current.component(.day, from: result) == 30)
    }

    @Test("displayDate round-trips a weekly day-of-week through dayOfWeek(for:)")
    func displayDateRoundTripsWeekly() {
        let reference = localDate(year: 2026, month: 3, day: 18) // a Wednesday
        for iso in Int32(1)...7 {
            let result = FixedExpenseScheduling.displayDate(dayOfMonth: 0, dayOfWeek: iso, isWeekly: true, referenceDate: reference)
            #expect(FixedExpenseScheduling.dayOfWeek(for: result) == iso)
        }
    }

    @Test("endDate computes N-1 monthly intervals from the anchor")
    func endDateFromPaymentsMonthly() {
        let anchor = localDate(year: 2026, month: 1, day: 15)
        // 6 monthly payments starting Jan 15 -> last payment June 15.
        let result = FixedExpenseScheduling.endDate(fromTotalPayments: 6, anchor: anchor, frequencyUnit: .month, intervalMonths: 1, intervalWeeks: 1)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: result!)
        #expect(components.year == 2026 && components.month == 6 && components.day == 15)
    }

    @Test("endDate computes N-1 weekly intervals from the anchor")
    func endDateFromPaymentsWeekly() {
        let anchor = localDate(year: 2026, month: 1, day: 5) // a Monday
        // 4 payments every 2 weeks starting Jan 5 -> last payment Feb 16 (3 * 2 weeks later).
        let result = FixedExpenseScheduling.endDate(fromTotalPayments: 4, anchor: anchor, frequencyUnit: .week, intervalMonths: 1, intervalWeeks: 2)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: result!)
        #expect(components.year == 2026 && components.month == 2 && components.day == 16)
    }

    @Test("endDate returns nil for zero or negative payments")
    func endDateNilForNonPositivePayments() {
        let anchor = localDate(year: 2026, month: 1, day: 15)
        #expect(FixedExpenseScheduling.endDate(fromTotalPayments: 0, anchor: anchor, frequencyUnit: .month, intervalMonths: 1, intervalWeeks: 1) == nil)
    }

    @Test("totalPayments is the inverse of endDate for monthly intervals")
    func totalPaymentsFromEndDateMonthly() {
        let anchor = localDate(year: 2026, month: 1, day: 15)
        let end = localDate(year: 2026, month: 6, day: 15)
        #expect(FixedExpenseScheduling.totalPayments(fromEndDate: end, anchor: anchor, frequencyUnit: .month, intervalMonths: 1, intervalWeeks: 1) == 6)
    }

    @Test("totalPayments is the inverse of endDate for weekly intervals")
    func totalPaymentsFromEndDateWeekly() {
        let anchor = localDate(year: 2026, month: 1, day: 5)
        let end = localDate(year: 2026, month: 2, day: 16)
        #expect(FixedExpenseScheduling.totalPayments(fromEndDate: end, anchor: anchor, frequencyUnit: .week, intervalMonths: 1, intervalWeeks: 2) == 4)
    }

    @Test("totalPayments never returns less than 1")
    func totalPaymentsMinimumOne() {
        let anchor = localDate(year: 2026, month: 6, day: 15)
        let end = localDate(year: 2026, month: 1, day: 15) // before the anchor
        #expect(FixedExpenseScheduling.totalPayments(fromEndDate: end, anchor: anchor, frequencyUnit: .month, intervalMonths: 1, intervalWeeks: 1) == 1)
    }

}
