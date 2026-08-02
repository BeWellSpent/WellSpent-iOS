import Testing
import Foundation
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
}
