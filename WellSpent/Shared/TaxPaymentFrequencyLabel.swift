import Foundation
import WellSpentAPI

/// Display text for a `TaxPaymentFrequency`.
nonisolated enum TaxPaymentFrequencyLabel {
    static func text(for frequency: Wellspent_V1_TaxPaymentFrequency) -> String {
        let locale = AppLanguageStore.currentLocale
        switch frequency {
        case .unspecified: return String(localized: "Not set", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .monthly: return String(localized: "Monthly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .quarterly: return String(localized: "Quarterly", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .fourMonthly: return String(localized: "Every 4 months", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .semiAnnual: return String(localized: "Semi-annual", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .annual: return String(localized: "Annual", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// All selectable frequencies, in display order, for pickers.
    static let selectable: [Wellspent_V1_TaxPaymentFrequency] = [
        .monthly, .quarterly, .fourMonthly, .semiAnnual, .annual,
    ]
}
