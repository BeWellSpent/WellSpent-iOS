import Foundation

/// Localized weekday/month names for the income pay-schedule pickers —
/// sourced from `Calendar` itself (already localized data, not our own
/// string catalog) rather than a `switch`-based `*Label` enum.
nonisolated enum CalendarSymbolLabel {
    /// 1 = Monday ... 7 = Sunday (ISO 8601).
    static func weekday(isoWeekday: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = AppLanguageStore.currentLocale
        // `weekdaySymbols` is always Sunday-first regardless of locale.
        let index = ((isoWeekday % 7) + 7) % 7
        return calendar.weekdaySymbols[index]
    }

    /// 1 = January ... 12 = December.
    static func month(_ month: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = AppLanguageStore.currentLocale
        let index = ((month - 1) % 12 + 12) % 12
        return calendar.monthSymbols[index]
    }

    static let isoWeekdays: [Int] = Array(1...7)
    static let months: [Int] = Array(1...12)
}
