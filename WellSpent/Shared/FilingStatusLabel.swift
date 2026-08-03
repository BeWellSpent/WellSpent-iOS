import Foundation
import WellSpentAPI

/// Display text for a `FilingStatus`.
nonisolated enum FilingStatusLabel {
    static func text(for status: Wellspent_V1_FilingStatus) -> String {
        let locale = AppLanguageStore.currentLocale
        switch status {
        case .unspecified: return String(localized: "Not set", locale: locale)
        case .single: return String(localized: "Single", locale: locale)
        case .marriedFilingJointly: return String(localized: "Married Filing Jointly", locale: locale)
        case .marriedFilingSeparately: return String(localized: "Married Filing Separately", locale: locale)
        case .headOfHousehold: return String(localized: "Head of Household", locale: locale)
        case .qualifyingSurvivingSpouse: return String(localized: "Qualifying Surviving Spouse", locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", locale: locale)
        }
    }

    /// All selectable statuses, in display order, for pickers.
    static let selectable: [Wellspent_V1_FilingStatus] = [
        .single, .marriedFilingJointly, .marriedFilingSeparately, .headOfHousehold, .qualifyingSurvivingSpouse,
    ]
}
