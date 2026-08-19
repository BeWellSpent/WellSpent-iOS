import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("InstallmentPlan")
struct InstallmentPlanTests {
    private func cents(_ amount: (units: Int64, nanos: Int32)) -> Int64 {
        amount.units * 100 + Int64(amount.nanos) / 10_000_000
    }

    private func money(_ units: Int64, _ nanos: Int32 = 0) -> (units: Int64, nanos: Int32) {
        (units: units, nanos: nanos)
    }

    @Test("splits evenly when the total divides cleanly")
    func evenSplit() {
        #expect(cents(InstallmentPlan.amount(total: money(900), payments: 3)) == 30000)
    }

    // The residue is structural: a fixed expense carries one planned amount
    // that every payment inherits, so no payment can absorb the difference.
    @Test("rounds to the nearest cent, leaving the plan a cent short")
    func roundsDown() {
        #expect(cents(InstallmentPlan.amount(total: money(1000), payments: 3)) == 33333)
    }

    @Test("rounds up when that is nearer")
    func roundsUp() {
        #expect(cents(InstallmentPlan.amount(total: money(1000), payments: 7)) == 14286)
    }

    @Test("an exact half cent rounds away from zero")
    func halfRoundsAway() {
        // 0.05 / 2 = 0.025 exactly -> 0.03, not 0.02.
        #expect(cents(InstallmentPlan.amount(total: money(0, 50_000_000), payments: 2)) == 3)
    }

    @Test("a zero payment count yields zero rather than trapping on divide-by-zero")
    func zeroPayments() {
        #expect(cents(InstallmentPlan.amount(total: money(1000), payments: 0)) == 0)
    }

    // A card bills the statement after the one you bought in.
    @Test("the default first payment is one month after the purchase")
    func defaultFirstPayment() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let purchase = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18))!
        let first = InstallmentPlan.defaultFirstPayment(purchase: purchase, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: first) ==
                DateComponents(year: 2026, month: 9, day: 18))
    }

    // Off by one here would spawn a whole extra payment.
    @Test("the end date is the last payment, not one past it")
    func endDateIsLastPayment() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let end = InstallmentPlan.endDate(firstPayment: first, payments: 4, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: end) ==
                DateComponents(year: 2026, month: 12, day: 18))
    }

    @Test("payment count and end date are inverses of each other")
    func roundTrip() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let end = InstallmentPlan.endDate(firstPayment: first, payments: 6, calendar: calendar)
        #expect(InstallmentPlan.payments(firstPayment: first, endDate: end, calendar: calendar) == 6)
    }

    @Test("never reports fewer than one payment when the end precedes the first")
    func neverBelowOne() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let earlier = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!
        #expect(InstallmentPlan.payments(firstPayment: first, endDate: earlier, calendar: calendar) == 1)
    }

    // Mirrors the backend's guards, so the action isn't offered where the RPC
    // would refuse it.
    @Test("only a variable spend can be split")
    func canSplitRules() {
        func tx(typeID: Int32 = 2, units: Int64 = 1000, planID: String = "") -> Wellspent_V1_Transaction {
            .with {
                $0.transactionTypeID = typeID
                $0.amount = .with { $0.units = units }
                $0.installmentFixedExpenseID = planID
            }
        }
        #expect(InstallmentPlan.canSplit(tx()))
        #expect(!InstallmentPlan.canSplit(tx(typeID: 1)), "Fixed is already the recurring thing")
        #expect(!InstallmentPlan.canSplit(tx(planID: "fe-1")), "already a plan")
        #expect(!InstallmentPlan.canSplit(tx(units: -1000)), "a negative amount is money received")
        #expect(!InstallmentPlan.canSplit(tx(units: 0)))
    }
}
