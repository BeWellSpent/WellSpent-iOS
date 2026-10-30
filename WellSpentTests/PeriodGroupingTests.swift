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

    private func makeRangedPeriod(
        id: String,
        startYear: Int, startMonth: Int, startDay: Int,
        endYear: Int, endMonth: Int, endDay: Int,
        isArchived: Bool = false
    ) -> Wellspent_V1_BudgetPeriod {
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            var components = DateComponents()
            components.year = y
            components.month = m
            components.day = d
            components.hour = 12
            return Calendar.current.date(from: components)!
        }
        return .with {
            $0.id = id
            $0.startDate = Google_Protobuf_Timestamp(dateOnly: date(startYear, startMonth, startDay))
            $0.endDate = Google_Protobuf_Timestamp(dateOnly: date(endYear, endMonth, endDay))
            $0.isArchived = isArchived
        }
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    @Test("resolveActivePeriod picks the period whose range actually contains today, over a newer non-archived one")
    func resolveActivePeriodPicksPeriodContainingToday() {
        let previous = makeRangedPeriod(id: "previous", startYear: 2026, startMonth: 9, startDay: 1, endYear: 2026, endMonth: 9, endDay: 30)
        let current = makeRangedPeriod(id: "current", startYear: 2026, startMonth: 10, startDay: 1, endYear: 2026, endMonth: 10, endDay: 31)
        let today = makeDate(2026, 10, 15)
        #expect(PeriodGrouping.resolveActivePeriod([previous, current], today: today)?.id == "current")
    }

    @Test("resolveActivePeriod resolves by date, not always-newest, when today falls inside what should be the previous period")
    func resolveActivePeriodPicksPreviousPeriodWhenTodayIsThere() {
        // Both non-archived — current cycling behavior keeps the previous
        // period non-archived too (see docs/features/month-cycling-review.md)
        // — so "newest non-archived" would wrongly return `current` here.
        let previous = makeRangedPeriod(id: "previous", startYear: 2026, startMonth: 9, startDay: 1, endYear: 2026, endMonth: 9, endDay: 30)
        let current = makeRangedPeriod(id: "current", startYear: 2026, startMonth: 10, startDay: 1, endYear: 2026, endMonth: 10, endDay: 31)
        let today = makeDate(2026, 9, 15)
        #expect(PeriodGrouping.resolveActivePeriod([previous, current], today: today)?.id == "previous")
    }

    @Test("resolveActivePeriod falls back to the newest non-archived period when today is inside no period's range")
    func resolveActivePeriodFallsBackWhenTodayMatchesNothing() {
        let archived = makeRangedPeriod(id: "archived", startYear: 2026, startMonth: 8, startDay: 1, endYear: 2026, endMonth: 8, endDay: 31, isArchived: true)
        let nonArchived = makeRangedPeriod(id: "non-archived", startYear: 2026, startMonth: 9, startDay: 1, endYear: 2026, endMonth: 9, endDay: 30)
        // The cycling job hasn't run yet — today is past every known period's end date.
        let today = makeDate(2026, 10, 15)
        #expect(PeriodGrouping.resolveActivePeriod([archived, nonArchived], today: today)?.id == "non-archived")
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

    @Test("periodsInSameYear includes archived periods sharing the reference period's year")
    func periodsInSameYearIncludesArchived() {
        let jan = makePeriod(id: "jan", year: 2026, month: 1, day: 1, isArchived: true)
        let jul = makePeriod(id: "jul", year: 2026, month: 7, day: 1)
        let prevDec = makePeriod(id: "dec25", year: 2025, month: 12, day: 1, isArchived: true)
        let result = PeriodGrouping.periodsInSameYear(as: jul, from: [jan, jul, prevDec])
        #expect(Set(result.map(\.id)) == ["jan", "jul"])
    }

}
