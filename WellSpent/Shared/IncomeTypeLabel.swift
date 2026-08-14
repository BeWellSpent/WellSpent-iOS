import Foundation
import WellSpentAPI

/// Display text for an `IncomeType`.
nonisolated enum IncomeTypeLabel {
    static func text(for type: Wellspent_V1_IncomeType) -> String {
        let locale = AppLanguageStore.currentLocale
        switch type {
        case .unspecified: return String(localized: "Unspecified", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .salary: return String(localized: "Salary", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .hourly: return String(localized: "Hourly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .freelance: return String(localized: "Freelance", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .contractor: return String(localized: "Contractor", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .investment: return String(localized: "Investment", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .interest: return String(localized: "Interest", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .oneTime: return String(localized: "One-time", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .gift: return String(localized: "Gift", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .other: return String(localized: "Other", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// All selectable types, in display order, for pickers.
    static let selectable: [Wellspent_V1_IncomeType] = [
        .salary, .hourly, .freelance, .contractor, .investment, .interest, .oneTime, .gift, .other,
    ]
}
