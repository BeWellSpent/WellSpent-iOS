import Foundation

/// Display label for a savings source's schedule, derived purely from how
/// many `payment_days` are set — mirrors web's `inferFrequencyLabel`. There
/// is no frequency picker anywhere in the create/edit forms; the count of
/// selected calendar days *is* the frequency.
nonisolated enum SavingsFrequencyLabel {
    static func text(forDayCount count: Int) -> String {
        let locale = AppLanguageStore.currentLocale
        switch count {
        case 1: return String(localized: "Monthly", locale: locale)
        case 2: return String(localized: "Bi-weekly", locale: locale)
        case 4: return String(localized: "Weekly", locale: locale)
        default: return ""
        }
    }
}
