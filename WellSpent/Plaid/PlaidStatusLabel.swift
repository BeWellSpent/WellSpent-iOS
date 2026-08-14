import Foundation

/// Display text for a Plaid connection's raw wire status
/// (`active`/`disconnected`/`error`, `plaid_item.status`). Mirrors
/// `PlaidStatusColor`'s "raw wire string, not a proto enum" shim pattern.
nonisolated enum PlaidStatusLabel {
    static func text(for status: String) -> String {
        let locale = AppLanguageStore.currentLocale
        switch status {
        case "active": return String(localized: "Active", bundle: AppLanguageStore.currentBundle, locale: locale)
        case "disconnected": return String(localized: "Disconnected", bundle: AppLanguageStore.currentBundle, locale: locale)
        case "error": return String(localized: "Error", bundle: AppLanguageStore.currentBundle, locale: locale)
        default: return status
        }
    }
}
