import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("IncomeJobGrouping")
struct IncomeJobGroupingTests {
    private func source(id: Int64, name: String = "Paycheck", personID: Int64 = 1, type: Wellspent_V1_IncomeType = .salary, frequency: Wellspent_V1_RecurringType = .monthly) -> Wellspent_V1_IncomeSource {
        .with {
            $0.id = id
            $0.name = name
            $0.budgetPersonID = personID
            $0.incomeType = type
            $0.paymentFrequency = frequency
        }
    }

    @Test("two rows sharing name/person/type/frequency group into one job")
    func groupsMatchingRows() {
        let sources = [source(id: 1), source(id: 2)]
        let jobs = IncomeJobGrouping.group(sources: sources, schedules: [:])
        #expect(jobs.count == 1)
        #expect(jobs[0].rows.count == 2)
    }

    @Test("a different name, person, type, or frequency starts a separate job")
    func differentKeySplitsJobs() {
        let byName = IncomeJobGrouping.group(sources: [source(id: 1, name: "A"), source(id: 2, name: "B")], schedules: [:])
        #expect(byName.count == 2)

        let byPerson = IncomeJobGrouping.group(sources: [source(id: 1, personID: 1), source(id: 2, personID: 2)], schedules: [:])
        #expect(byPerson.count == 2)

        let byType = IncomeJobGrouping.group(sources: [source(id: 1, type: .salary), source(id: 2, type: .freelance)], schedules: [:])
        #expect(byType.count == 2)

        let byFrequency = IncomeJobGrouping.group(sources: [source(id: 1, frequency: .monthly), source(id: 2, frequency: .biWeekly)], schedules: [:])
        #expect(byFrequency.count == 2)
    }

    @Test("rows within a job are sorted by anchor date ascending, nil first")
    func rowsSortedByAnchorDate() {
        let calendar = Calendar(identifier: .gregorian)
        let early = calendar.date(from: .init(year: 2026, month: 1, day: 1))!
        let late = calendar.date(from: .init(year: 2026, month: 1, day: 15))!
        let sources = [source(id: 1), source(id: 2), source(id: 3)]
        let schedules: [Int64: BudgetRESTMapping.IncomeSchedule] = [
            1: .init(anchorDate: late, earlyArrivalToleranceDays: 0),
            2: .init(anchorDate: nil, earlyArrivalToleranceDays: 0),
            3: .init(anchorDate: early, earlyArrivalToleranceDays: 0),
        ]
        let jobs = IncomeJobGrouping.group(sources: sources, schedules: schedules)
        #expect(jobs[0].rows.map(\.source.id) == [2, 3, 1])
    }

    @Test("totalAmount sums every row's amount")
    func totalAmountSums() {
        let source1 = Wellspent_V1_IncomeSource.with { $0.id = 1; $0.budgetPersonID = 1; $0.defaultAmount = .with { $0.units = 2000 } }
        let source2 = Wellspent_V1_IncomeSource.with { $0.id = 2; $0.budgetPersonID = 1; $0.defaultAmount = .with { $0.units = 2000 } }
        let jobs = IncomeJobGrouping.group(sources: [source1, source2], schedules: [:])
        #expect(jobs[0].totalAmount.units == 4000)
    }
}
