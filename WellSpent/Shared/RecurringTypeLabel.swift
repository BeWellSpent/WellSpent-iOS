import Foundation
import WellSpentAPI

/// Display text for a `RecurringType` (used as income's payment frequency).
nonisolated enum RecurringTypeLabel {
    static func text(for type: Wellspent_V1_RecurringType) -> String {
        let locale = AppLanguageStore.currentLocale
        switch type {
        case .unspecified: return String(localized: "Unspecified", locale: locale)
        case .oneOff: return String(localized: "One-off", locale: locale)
        case .weekly: return String(localized: "Weekly", locale: locale)
        case .biWeekly: return String(localized: "Bi-weekly", locale: locale)
        case .monthly: return String(localized: "Monthly", locale: locale)
        case .yearly: return String(localized: "Yearly", locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", locale: locale)
        }
    }

    /// All selectable frequencies, in display order, for pickers.
    static let selectable: [Wellspent_V1_RecurringType] = [.oneOff, .weekly, .biWeekly, .monthly, .yearly]
}
