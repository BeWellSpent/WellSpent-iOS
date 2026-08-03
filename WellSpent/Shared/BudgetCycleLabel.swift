import Foundation
import WellSpentAPI

/// Display text for a `BudgetCycle`.
nonisolated enum BudgetCycleLabel {
    static func text(for cycle: Wellspent_V1_BudgetCycle) -> String {
        let locale = AppLanguageStore.currentLocale
        switch cycle {
        case .unspecified:
            return String(localized: "Unspecified", locale: locale)
        case .weekly:
            return String(localized: "Weekly", locale: locale)
        case .biWeekly:
            return String(localized: "Bi-weekly", locale: locale)
        case .monthly:
            return String(localized: "Monthly", locale: locale)
        case .yearly:
            return String(localized: "Yearly", locale: locale)
        case .UNRECOGNIZED:
            return String(localized: "Unknown", locale: locale)
        }
    }

    /// All selectable cycles, in display order, for pickers.
    static let selectable: [Wellspent_V1_BudgetCycle] = [.weekly, .biWeekly, .monthly, .yearly]
}
