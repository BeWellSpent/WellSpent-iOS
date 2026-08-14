import Foundation
import WellSpentAPI

/// Display text for a `FilingStatus`.
nonisolated enum FilingStatusLabel {
    static func text(for status: Wellspent_V1_FilingStatus) -> String {
        let locale = AppLanguageStore.currentLocale
        switch status {
        case .unspecified: return String(localized: "Not set", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .single: return String(localized: "Single", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .marriedFilingJointly: return String(localized: "Married Filing Jointly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .marriedFilingSeparately: return String(localized: "Married Filing Separately", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .headOfHousehold: return String(localized: "Head of Household", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .qualifyingSurvivingSpouse: return String(localized: "Qualifying Surviving Spouse", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// All selectable statuses, in display order, for pickers.
    static let selectable: [Wellspent_V1_FilingStatus] = [
        .single, .marriedFilingJointly, .marriedFilingSeparately, .headOfHousehold, .qualifyingSurvivingSpouse,
    ]
}
