import Foundation

/// `AlertSubscription.threshold_scope` is a plain string on the wire
/// (`notification.proto`), only meaningful for `AlertType.spendingThreshold`.
nonisolated enum ThresholdScope: String, CaseIterable {
    case budget
    case category

    var label: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .budget: return String(localized: "Whole Budget", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .category: return String(localized: "Per Category", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }
}
