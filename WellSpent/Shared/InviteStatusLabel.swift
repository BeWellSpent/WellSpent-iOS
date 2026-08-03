import Foundation
import WellSpentAPI

/// Display text for an `InviteStatus`.
nonisolated enum InviteStatusLabel {
    static func text(for status: Wellspent_V1_InviteStatus) -> String {
        let locale = AppLanguageStore.currentLocale
        switch status {
        case .unspecified: return String(localized: "Unknown", locale: locale)
        case .pending: return String(localized: "Pending", locale: locale)
        case .accepted: return String(localized: "Accepted", locale: locale)
        case .cancelled: return String(localized: "Cancelled", locale: locale)
        case .expired: return String(localized: "Expired", locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", locale: locale)
        }
    }
}
