import Foundation
import WellSpentAPI

struct PeriodYearGroup: Identifiable {
    let year: Int
    let periods: [Wellspent_V1_BudgetPeriod]
    var id: Int { year }
}

/// Groups periods by calendar year, derived from `start_date` via `.dateOnly`
/// (the DATE-only UTC-midnight-to-local-day conversion — see `DateOnly.swift`;
/// using `.date`/raw UTC components here instead would risk an off-by-one
/// year near a year boundary in negative-UTC-offset timezones, the same
/// class of bug `.dateOnly` already exists to prevent). Years are returned
/// most-recent-first; periods within a year are sorted most-recent-first.
nonisolated enum PeriodGrouping {
    static func groupByYear(_ periods: [Wellspent_V1_BudgetPeriod]) -> [PeriodYearGroup] {
        var byYear: [Int: [Wellspent_V1_BudgetPeriod]] = [:]
        for period in periods {
            let year = Calendar.current.component(.year, from: period.startDate.dateOnly)
            byYear[year, default: []].append(period)
        }

        return byYear.keys.sorted(by: >).map { year in
            let sorted = byYear[year]!.sorted { $0.startDate.seconds > $1.startDate.seconds }
            return PeriodYearGroup(year: year, periods: sorted)
        }
    }

    /// The period whose `[startDate, endDate]` range actually contains
    /// today's local calendar date — "current", not "newest non-archived".
    /// Those used to coincide by construction when only the latest period
    /// was ever non-archived, but the backend now keeps the current *and*
    /// previous period both non-archived permanently (see
    /// docs/features/month-cycling-review.md), so that coincidence can no
    /// longer be relied on. Falls back to the most recent non-archived
    /// period (then the newest overall) when no period's range contains
    /// today — e.g. the cycling job hasn't run yet and today has rolled
    /// past every known period's end date.
    static func resolveActivePeriod(_ periods: [Wellspent_V1_BudgetPeriod], today: Date = Date()) -> Wellspent_V1_BudgetPeriod? {
        let todayStart = Calendar.current.startOfDay(for: today)
        if let containing = periods.first(where: { period in
            period.startDate.dateOnly <= todayStart && todayStart <= period.endDate.dateOnly
        }) {
            return containing
        }
        return periods
            .filter { !$0.isArchived }
            .max { $0.startDate.seconds < $1.startDate.seconds }
            ?? periods.max { $0.startDate.seconds < $1.startDate.seconds }
    }

    /// Resolves which period to display: the explicit `overrideID` if it
    /// matches one of `periods`, otherwise the active period. Falls back to
    /// the active period if `overrideID` doesn't match anything.
    static func resolvePeriod(_ periods: [Wellspent_V1_BudgetPeriod], overrideID: String?) -> Wellspent_V1_BudgetPeriod? {
        guard let overrideID, !overrideID.isEmpty else { return resolveActivePeriod(periods) }
        return periods.first { $0.id == overrideID } ?? resolveActivePeriod(periods)
    }

    /// Periods sharing a calendar year with `period`, including archived
    /// ones — backs the Transactions screen's period switcher
    /// (`TransactionsPeriodControl`), relocated from the former ☰ menu's
    /// period section (issue #92 follow-up).
    static func periodsInSameYear(as period: Wellspent_V1_BudgetPeriod, from periods: [Wellspent_V1_BudgetPeriod]) -> [Wellspent_V1_BudgetPeriod] {
        let year = Calendar.current.component(.year, from: period.startDate.dateOnly)
        return periods.filter { Calendar.current.component(.year, from: $0.startDate.dateOnly) == year }
    }

    /// A localized "July 2026"-style label for a period row — mirrors
    /// `TransactionDayGrouping.headerText`'s locale-aware formatting.
    static func label(for period: Wellspent_V1_BudgetPeriod, localeIdentifier: String) -> String {
        period.startDate.dateOnly.formatted(
            Date.FormatStyle(locale: Locale(identifier: localeIdentifier))
                .month(.wide)
                .year()
        )
    }
}
