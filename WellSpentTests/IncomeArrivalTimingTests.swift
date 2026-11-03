import Testing
import Foundation
import WellSpentAPI
@testable import WellSpent

@Suite("IncomeArrivalTiming")
struct IncomeArrivalTimingTests {
    private func transaction(dateOnly date: Date) -> Wellspent_V1_Transaction {
        .with { $0.date = Google_Protobuf_Timestamp(dateOnly: date) }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    /// Matches real usage (`BudgetDetailView` always passes
    /// `period.startDate.dateOnly`) — the production comparison is between
    /// two `.dateOnly` values, both local midnight, so the test's
    /// `periodStartDate` has to go through the same round trip rather than
    /// a raw noon `Date` that would spuriously compare later than midnight.
    private func periodStart(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Google_Protobuf_Timestamp(dateOnly: date(year, month, day)).dateOnly
    }

    @Test("true when the transaction is dated before the period it's assigned to starts")
    func arrivedEarly() {
        let tx = transaction(dateOnly: date(2026, 10, 30))
        #expect(IncomeArrivalTiming.arrivedEarly(tx, periodStartDate: periodStart(2026, 11, 1)))
    }

    @Test("false when dated on or after the period's start")
    func notArrivedEarly() {
        let onStart = transaction(dateOnly: date(2026, 11, 1))
        #expect(!IncomeArrivalTiming.arrivedEarly(onStart, periodStartDate: periodStart(2026, 11, 1)))

        let after = transaction(dateOnly: date(2026, 11, 5))
        #expect(!IncomeArrivalTiming.arrivedEarly(after, periodStartDate: periodStart(2026, 11, 1)))
    }
}
