import Foundation
import WellSpentAPI

/// Display text for a `BudgetCycle`.
nonisolated enum BudgetCycleLabel {
    static func text(for cycle: Wellspent_V1_BudgetCycle) -> String {
        let locale = AppLanguageStore.currentLocale
        switch cycle {
        case .unspecified:
            return String(localized: "Unspecified", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .weekly:
            return String(localized: "Weekly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .biWeekly:
            return String(localized: "Bi-weekly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .monthly:
            return String(localized: "Monthly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .yearly:
            return String(localized: "Yearly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .UNRECOGNIZED:
            return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// All selectable cycles, in display order, for pickers.
    static let selectable: [Wellspent_V1_BudgetCycle] = [.weekly, .biWeekly, .monthly, .yearly]
}
