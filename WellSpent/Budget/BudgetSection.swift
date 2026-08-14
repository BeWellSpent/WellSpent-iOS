import Foundation

/// Top-level destination within a budget: shown as a bottom tab bar on
/// iPhone and a sidebar (`NavigationSplitView`) on iPad. Collapses web's two
/// independent nav layers (top tabs for Plan/Transactions/... + a separate
/// sidebar/drawer for Income/Savings/Payment Methods/Categories/People) into
/// one adaptive structure — iOS has no good native equivalent of a second
/// persistent nav rail alongside a tab bar.
enum BudgetSection: CaseIterable, Hashable {
    case plan
    case transactions
    case review
    case manage

    var title: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .plan: return String(localized: "Plan", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .transactions: return String(localized: "Transactions", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .review: return String(localized: "Review", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .manage: return String(localized: "Manage", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    var systemImage: String {
        switch self {
        case .plan: return "chart.pie"
        case .transactions: return "list.bullet"
        case .review: return "checkmark.circle"
        case .manage: return "slider.horizontal.3"
        }
    }
}
