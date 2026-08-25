import Foundation

/// Top-level destination within a budget: shown as a bottom tab bar on
/// iPhone and a sidebar (`NavigationSplitView`) on iPad.
///
/// These four are the whole of the app's primary navigation — the budget is
/// the home screen, so there is no list above this. Everything that isn't a
/// frequent destination (period switching, the manage panels, settings,
/// help, logging out) lives in `BudgetMenuSheet` behind the ☰, which is what
/// keeps this bar down to four. Mirrors web's `BudgetView` tabs exactly; see
/// docs/features/main-view-rework.md.
enum BudgetSection: CaseIterable, Hashable {
    case plan
    case transactions
    case review
    case reports

    /// The label under the tab icon. Deliberately shorter than `screenTitle`
    /// — a tab bar has ~80pt per item, and "Expense Plan" truncates there.
    var title: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .plan: return String(localized: "Plan", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .transactions: return String(localized: "Transactions", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .review: return String(localized: "Review", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .reports: return String(localized: "Reports", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// What the navigation bar prints in the middle. Fuller than `title`
    /// because there is room for it, and because the bar is now the only
    /// thing naming the current view — the budget's own name moved into the
    /// ☰ menu.
    var screenTitle: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .plan: return String(localized: "Expense Plan", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .transactions: return String(localized: "Transactions", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .review: return String(localized: "Review", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .reports: return String(localized: "Reports", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    var systemImage: String {
        switch self {
        case .plan: return "chart.pie"
        case .transactions: return "list.bullet"
        case .review: return "checkmark.circle"
        case .reports: return "chart.bar.doc.horizontal"
        }
    }
}
