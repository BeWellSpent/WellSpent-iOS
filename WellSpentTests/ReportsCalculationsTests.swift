import Foundation
import Testing
@testable import WellSpent

@Suite("ReportsCalculations")
struct ReportsCalculationsTests {
    @Test("Free can only choose the 3-period range; Pro any")
    func ranges() {
        #expect(!ReportsCalculations.isRangeLocked(3, isPro: false))
        #expect(ReportsCalculations.isRangeLocked(6, isPro: false))
        #expect(ReportsCalculations.isRangeLocked(12, isPro: false))
        #expect(!ReportsCalculations.isRangeLocked(12, isPro: true))
    }

    @Test("A scorecard row's status: locked and in-progress win, then no plan, then the score")
    func scorecardStatus() {
        typealias C = ReportsCalculations
        #expect(C.scorecardStatus(locked: true, inProgress: true, planRecorded: true, onPlan: true) == .locked)
        #expect(C.scorecardStatus(locked: false, inProgress: true, planRecorded: true, onPlan: nil) == .inProgress)
        #expect(C.scorecardStatus(locked: false, inProgress: false, planRecorded: false, onPlan: nil) == .noPlan)
        #expect(C.scorecardStatus(locked: false, inProgress: false, planRecorded: true, onPlan: true) == .onPlan)
        #expect(C.scorecardStatus(locked: false, inProgress: false, planRecorded: true, onPlan: false) == .over)
        #expect(C.scorecardStatus(locked: false, inProgress: false, planRecorded: true, onPlan: nil) == .notScored)
    }

    @Test("Percentages keep a decimal under 10%")
    func percents() {
        #expect(ReportsCalculations.percentText(41.4) == "41%")
        #expect(ReportsCalculations.percentText(2.8) == "2.8%")
        #expect(ReportsCalculations.percentText(-3.25) == "-3.2%" || ReportsCalculations.percentText(-3.25) == "-3.3%")
    }

    @Test("Column totals are compact: thousands shortened to one decimal")
    func compactMoney() {
        #expect(ReportsCalculations.compactMoneyText((4574, 0), currencyCode: "USD", localeIdentifier: "en") == "$4.6k")
        #expect(ReportsCalculations.compactMoneyText((820, 0), currencyCode: "USD", localeIdentifier: "en") == "$820")
    }

    @Test("An increase is more spending")
    func increase() {
        #expect(ReportsCalculations.isIncrease((80, 0)))
        #expect(!ReportsCalculations.isIncrease((-64, 0)))
    }
}
