import Foundation

/// Top-level destination within a budget: shown as a bottom tab bar on
/// iPhone and a sidebar (`NavigationSplitView`) on iPad.
///
/// Four real destinations plus `more`, which is not a destination at all: it
/// presents `BudgetMenuSheet` and never becomes the selected tab. Everything
/// infrequent (period switching, the manage panels, settings, help, logging
/// out) lives in that sheet, which is what keeps the four real ones to four.
///
/// `more` sits in the bottom bar rather than the navigation bar because the
/// sheet rises from the bottom of the screen — that is where it should look
/// like it comes from. See docs/features/main-view-rework.md.
///
/// `home`/`plan` replaced the former `plan`/`transactions`/`review` split
/// (docs/features/overview-plan-navigation-rework.md): Home is the destination
/// for *what actually happened* — its own first sub-tab is named "Overview"
/// (totals + the actual-breakdown chart, one combined panel), alongside
/// Transactions/Payments/Review sub-tabs — Plan is for *what you intend to
/// spend* (the per-category planned-amount editor). Renamed from `overview`
/// to `home` once "Overview" became the name of a sub-tab *within* this
/// section too — two things sharing one name in the same screen was confusing
/// rather than descriptive.
enum BudgetSection: CaseIterable, Hashable {
    case home
    case plan
    case reports
    /// Presents the menu sheet. Never becomes `selectedSection` — see
    /// `BudgetDetailView.tabSelection`.
    case more

    /// The label under the tab icon. Deliberately shorter than `screenTitle`
    /// — a tab bar has ~80pt per item, and "Expense Plan" truncates there.
    var title: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .home: return String(localized: "Home", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .plan: return String(localized: "Plan", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .reports: return String(localized: "Reports", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .more: return String(localized: "More", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// What the navigation bar prints in the middle. Fuller than `title`
    /// because there is room for it, and because the bar is now the only
    /// thing naming the current view — the budget's own name moved into the
    /// ☰ menu.
    var screenTitle: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .home: return String(localized: "Home", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .plan: return String(localized: "Expense Plan", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .reports: return String(localized: "Reports", bundle: AppLanguageStore.currentBundle, locale: locale)
        // Never displayed — `more` is never the selected section.
        case .more: return String(localized: "More", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }

    /// `home` uses a house glyph, matching its name — no more need to dodge
    /// `.plan`'s `chart.pie` the way the old `.overview` case did, since
    /// neither icon nor name collide with Plan anymore.
    var systemImage: String {
        switch self {
        case .home: return "house"
        case .plan: return "chart.pie"
        case .reports: return "chart.bar.doc.horizontal"
        case .more: return "ellipsis"
        }
    }
}
