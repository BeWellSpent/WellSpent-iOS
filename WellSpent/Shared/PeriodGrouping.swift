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

    /// The most recent non-archived period, falling back to the newest
    /// period overall if every period happens to be archived.
    static func resolveActivePeriod(_ periods: [Wellspent_V1_BudgetPeriod]) -> Wellspent_V1_BudgetPeriod? {
        periods
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
