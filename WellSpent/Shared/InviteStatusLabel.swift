import Foundation
import WellSpentAPI

/// Display text for an `InviteStatus`.
nonisolated enum InviteStatusLabel {
    static func text(for status: Wellspent_V1_InviteStatus) -> String {
        let locale = AppLanguageStore.currentLocale
        switch status {
        case .unspecified: return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .pending: return String(localized: "Pending", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .accepted: return String(localized: "Accepted", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .cancelled: return String(localized: "Cancelled", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .expired: return String(localized: "Expired", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }
}
