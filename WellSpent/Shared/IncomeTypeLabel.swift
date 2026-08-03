import Foundation
import WellSpentAPI

/// Display text for an `IncomeType`.
nonisolated enum IncomeTypeLabel {
    static func text(for type: Wellspent_V1_IncomeType) -> String {
        let locale = AppLanguageStore.currentLocale
        switch type {
        case .unspecified: return String(localized: "Unspecified", locale: locale)
        case .salary: return String(localized: "Salary", locale: locale)
        case .hourly: return String(localized: "Hourly", locale: locale)
        case .freelance: return String(localized: "Freelance", locale: locale)
        case .contractor: return String(localized: "Contractor", locale: locale)
        case .investment: return String(localized: "Investment", locale: locale)
        case .interest: return String(localized: "Interest", locale: locale)
        case .oneTime: return String(localized: "One-time", locale: locale)
        case .gift: return String(localized: "Gift", locale: locale)
        case .other: return String(localized: "Other", locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", locale: locale)
        }
    }

    /// All selectable types, in display order, for pickers.
    static let selectable: [Wellspent_V1_IncomeType] = [
        .salary, .hourly, .freelance, .contractor, .investment, .interest, .oneTime, .gift, .other,
    ]
}
