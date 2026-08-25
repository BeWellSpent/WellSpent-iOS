import Testing
import Foundation
import WellSpentAPI
@testable import WellSpent

@Suite("PeriodGrouping")
struct PeriodGroupingTests {
    private func makePeriod(id: String, year: Int, month: Int, day: Int, isArchived: Bool = false) -> Wellspent_V1_BudgetPeriod {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        let localDate = Calendar.current.date(from: components)!
        return .with {
            $0.id = id
            $0.startDate = Google_Protobuf_Timestamp(dateOnly: localDate)
            $0.isArchived = isArchived
        }
    }

    @Test("groups periods into the correct calendar year")
    func groupsByYear() {
        let jan2025 = makePeriod(id: "p1", year: 2025, month: 1, day: 1)
        let jul2026 = makePeriod(id: "p2", year: 2026, month: 7, day: 1)
        let groups = PeriodGrouping.groupByYear([jan2025, jul2026])
        #expect(groups.map(\.year) == [2026, 2025])
    }

    @Test("sorts periods within a year most-recent-first")
    func sortsWithinYear() {
        let jan = makePeriod(id: "jan", year: 2026, month: 1, day: 1)
        let jun = makePeriod(id: "jun", year: 2026, month: 6, day: 1)
        let groups = PeriodGrouping.groupByYear([jan, jun])
        #expect(groups.first?.periods.map(\.id) == ["jun", "jan"])
    }

    @Test("returns an empty array for no periods")
    func emptyInput() {
        #expect(PeriodGrouping.groupByYear([]).isEmpty)
    }

    @Test("resolveActivePeriod returns the non-archived period")
    func resolveActivePeriodPicksNonArchived() {
        let archived = makePeriod(id: "p1", year: 2026, month: 6, day: 1, isArchived: true)
        let active = makePeriod(id: "p2", year: 2026, month: 7, day: 1, isArchived: false)
        #expect(PeriodGrouping.resolveActivePeriod([archived, active])?.id == "p2")
    }

    @Test("resolveActivePeriod falls back to the newest period when all are archived")
    func resolveActivePeriodFallsBack() {
        let p1 = makePeriod(id: "p1", year: 2026, month: 5, day: 1, isArchived: true)
        let p2 = makePeriod(id: "p2", year: 2026, month: 6, day: 1, isArchived: true)
        #expect(PeriodGrouping.resolveActivePeriod([p1, p2])?.id == "p2")
    }

    @Test("resolvePeriod returns the active period when no override is given")
    func resolvePeriodNoOverride() {
        let archived = makePeriod(id: "p-archived", year: 2026, month: 6, day: 1, isArchived: true)
        let active = makePeriod(id: "p-active", year: 2026, month: 7, day: 1, isArchived: false)
        #expect(PeriodGrouping.resolvePeriod([archived, active], overrideID: nil)?.id == "p-active")
    }

    @Test("resolvePeriod returns the overridden (archived) period when its id matches")
    func resolvePeriodWithOverride() {
        let archived = makePeriod(id: "p-archived", year: 2026, month: 6, day: 1, isArchived: true)
        let active = makePeriod(id: "p-active", year: 2026, month: 7, day: 1, isArchived: false)
        #expect(PeriodGrouping.resolvePeriod([archived, active], overrideID: "p-archived")?.id == "p-archived")
    }

    @Test("resolvePeriod falls back to the active period when the override id matches nothing")
    func resolvePeriodInvalidOverride() {
        let archived = makePeriod(id: "p-archived", year: 2026, month: 6, day: 1, isArchived: true)
        let active = makePeriod(id: "p-active", year: 2026, month: 7, day: 1, isArchived: false)
        #expect(PeriodGrouping.resolvePeriod([archived, active], overrideID: "does-not-exist")?.id == "p-active")
    }

    @Test("label formats a localized month + year")
    func labelFormatsMonthAndYear() {
        let period = makePeriod(id: "p1", year: 2026, month: 7, day: 15)
        let label = PeriodGrouping.label(for: period, localeIdentifier: "en")
        #expect(label.contains("July"))
        #expect(label.contains("2026"))
    }

}
