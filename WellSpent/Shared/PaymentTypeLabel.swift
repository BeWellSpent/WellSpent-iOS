import Foundation
import WellSpentAPI

/// Display text for a `PaymentType`.
nonisolated enum PaymentTypeLabel {
    static func text(for type: Wellspent_V1_PaymentType) -> String {
        let locale = AppLanguageStore.currentLocale
        switch type {
        case .unspecified: return String(localized: "Unspecified", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .cash: return String(localized: "Cash", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .credit: return String(localized: "Credit", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .debit: return String(localized: "Debit", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .digitalWallet: return String(localized: "Digital Wallet", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .bankTransfer: return String(localized: "Bank Transfer", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .crypto: return String(localized: "Crypto", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .investment: return String(localized: "Investment", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .other: return String(localized: "Other", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// All selectable types, in display order, for pickers.
    static let selectable: [Wellspent_V1_PaymentType] = [
        .cash, .credit, .debit, .digitalWallet, .bankTransfer, .crypto, .investment, .other,
    ]
}
