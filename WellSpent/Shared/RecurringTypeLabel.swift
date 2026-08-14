import Foundation
import WellSpentAPI

/// Display text for a `RecurringType` (used as income's payment frequency).
nonisolated enum RecurringTypeLabel {
    static func text(for type: Wellspent_V1_RecurringType) -> String {
        let locale = AppLanguageStore.currentLocale
        switch type {
        case .unspecified: return String(localized: "Unspecified", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .oneOff: return String(localized: "One-off", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .weekly: return String(localized: "Weekly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .biWeekly: return String(localized: "Bi-weekly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .monthly: return String(localized: "Monthly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .yearly: return String(localized: "Yearly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// All selectable frequencies, in display order, for pickers.
    static let selectable: [Wellspent_V1_RecurringType] = [.oneOff, .weekly, .biWeekly, .monthly, .yearly]
}
