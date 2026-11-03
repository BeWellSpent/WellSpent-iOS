import Foundation

/// Display text for a picked day-of-month (1-31), matching the Fixed
/// Expense day-of-month convention (`FixedExpenseScheduling`/backend's
/// `DateInMonth`: clamped to the real last day of whichever month it lands
/// in) — "31" reads as "Last day of month" rather than a bare number that
/// would silently clamp in a short month.
nonisolated enum DayOfMonthLabel {
    static func text(for day: Int) -> String {
        guard day == 31 else { return String(day) }
        return String(localized: "Last day of month", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
    }

    static let selectable: [Int] = Array(1...31)
}
