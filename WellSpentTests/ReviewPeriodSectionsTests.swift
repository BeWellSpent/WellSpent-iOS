import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("ReviewPeriodSections")
struct ReviewPeriodSectionsTests {
    private func period(_ id: String, start: Date) -> Wellspent_V1_BudgetPeriod {
        .with { $0.id = id; $0.startDate = .init(dateOnly: start) }
    }

    private func review(_ id: String, period: String, matched: String, score: Double, imported: Bool = true) -> Wellspent_V1_TransactionReview {
        .with {
            $0.id = id
            $0.budgetPeriodID = period
            $0.matchedTransactionID = matched
            $0.matchScore = score
            $0.transactionImported = imported
            $0.status = "pending"
        }
    }

    private let sep = Date(timeIntervalSince1970: 1_788_220_800) // 2026-09-01
    private let oct = Date(timeIntervalSince1970: 1_790_812_800) // 2026-10-01
    private let nov = Date(timeIntervalSince1970: 1_793_491_200) // 2026-11-01

    private var periods: [Wellspent_V1_BudgetPeriod] { [period("sep", start: sep), period("oct", start: oct), period("nov", start: nov)] }

    private var groups: [ReviewGroup] {
        ReviewGrouping.group([
            review("a", period: "sep", matched: "m1", score: 88),
            review("b", period: "nov", matched: "m2", score: 96),
            review("c", period: "nov", matched: "m3", score: 84, imported: false),
            review("d", period: "oct", matched: "m4", score: 93),
        ])
    }

    @Test("sections are per period, newest first, and the current one is marked")
    func groupsByPeriodNewestFirst() {
        let sections = ReviewPeriodSections.build(groups: groups, periods: periods, currentPeriodID: "nov", filter: ReviewFilter())
        #expect(sections.map(\.periodID) == ["nov", "oct", "sep"])
        #expect(sections.first?.isCurrent == true)
        #expect(sections.first?.groups.count == 2)
    }

    @Test("strong and possible split at 90")
    func strengthFilter() {
        let strong = ReviewPeriodSections.build(groups: groups, periods: periods, currentPeriodID: nil, filter: ReviewFilter(strength: .strong))
        #expect(strong.flatMap(\.groups).map(\.matchedTransactionID).sorted() == ["m2", "m4"])
        let possible = ReviewPeriodSections.build(groups: groups, periods: periods, currentPeriodID: nil, filter: ReviewFilter(strength: .possible))
        #expect(possible.flatMap(\.groups).map(\.matchedTransactionID).sorted() == ["m1", "m3"])
    }

    @Test("bank only drops typed-in matches; a period with nothing left disappears")
    func bankOnlyAndPeriodFilter() {
        let bank = ReviewPeriodSections.build(groups: groups, periods: periods, currentPeriodID: nil, filter: ReviewFilter(bankOnly: true))
        #expect(!bank.flatMap(\.groups).contains { $0.matchedTransactionID == "m3" })
        let onlyOct = ReviewPeriodSections.build(groups: groups, periods: periods, currentPeriodID: nil, filter: ReviewFilter(periodID: "oct"))
        #expect(onlyOct.map(\.periodID) == ["oct"])
        let none = ReviewPeriodSections.build(groups: groups, periods: periods, currentPeriodID: nil, filter: ReviewFilter(periodID: "sep", strength: .strong))
        #expect(none.isEmpty)
    }

    @Test("the period filter only offers periods with matches")
    func periodChoices() {
        let extra = periods + [period("aug", start: sep.addingTimeInterval(-2_678_400))]
        #expect(ReviewPeriodSections.periodsWithMatches(groups: groups, periods: extra).map(\.id) == ["nov", "oct", "sep"])
    }

    @Test("the detail line names the source, the card and the date")
    func detailLine() {
        var r = review("x", period: "nov", matched: "m", score: 90)
        r.transactionPaymentMethodName = "Checking"
        r.transactionDate = .init(dateOnly: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2))!)
        #expect(ReviewLineDetail.text(for: r, localeIdentifier: "en_US") == "Bank · Checking · Nov 2")
        r.transactionImported = false
        r.transactionPaymentMethodName = ""
        r.clearTransactionDate()
        #expect(ReviewLineDetail.text(for: r, localeIdentifier: "en_US") == "Typed in")
    }
}
