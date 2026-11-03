import Testing
import Foundation
import WellSpentAPI
@testable import WellSpent

@Suite("PayDateOrderingHint")
struct PayDateOrderingHintTests {
    private func localDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    @Test("flags pay day 1 later than pay day 2 for monthly frequency")
    func flagsOutOfOrderMonthly() {
        let dates = [localDate(year: 2026, month: 1, day: 31), localDate(year: 2026, month: 1, day: 15)]
        #expect(PayDateOrderingHint.message(for: dates, frequency: .monthly) != nil)
    }

    @Test("says nothing when already in ascending order")
    func silentWhenAscending() {
        let dates = [localDate(year: 2026, month: 1, day: 15), localDate(year: 2026, month: 1, day: 31)]
        #expect(PayDateOrderingHint.message(for: dates, frequency: .monthly) == nil)
    }

    @Test("says nothing with fewer than 2 pay dates")
    func silentWithOnePayDate() {
        let dates = [localDate(year: 2026, month: 1, day: 31)]
        #expect(PayDateOrderingHint.message(for: dates, frequency: .monthly) == nil)
    }

    @Test("says nothing for weekly/bi-weekly, where day-number ordering is meaningless")
    func silentForWeekly() {
        let dates = [localDate(year: 2026, month: 1, day: 31), localDate(year: 2026, month: 1, day: 15)]
        #expect(PayDateOrderingHint.message(for: dates, frequency: .biWeekly) == nil)
    }
}
