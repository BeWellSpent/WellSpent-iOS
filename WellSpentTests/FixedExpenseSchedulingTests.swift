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
}
