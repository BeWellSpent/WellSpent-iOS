import Foundation

/// `AlertSubscription.channel` is a plain string on the wire (`notification.proto`).
nonisolated enum AlertChannel: String, CaseIterable {
    case inApp = "in_app"
    case email
    case both

    var label: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .inApp: return String(localized: "In-App", locale: locale)
        case .email: return String(localized: "Email", locale: locale)
        case .both: return String(localized: "Both", locale: locale)
        }
    }
}
