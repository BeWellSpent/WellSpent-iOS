import Foundation
import WellSpentAPI

/// Display text for a `BudgetRole`. Mirrors web's `useRoleLabel` hook
/// (`WellSpent-web/src/components/budget/peoplePanel/useRoleLabel.ts`).
nonisolated enum BudgetRoleLabel {
    static func text(for role: Wellspent_V1_BudgetRole) -> String {
        let locale = AppLanguageStore.currentLocale
        switch role {
        case .unspecified:
            return String(localized: "No account", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .admin:
            return String(localized: "Admin", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .collaborator:
            return String(localized: "Collaborator", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .viewer:
            return String(localized: "Viewer", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .UNRECOGNIZED:
            return String(localized: "Unknown", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }
}
