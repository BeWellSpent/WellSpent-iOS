import SwiftUI
import WellSpentAPI
import WellSpentREST

/// The budget-wide settings shown beneath the per-person chart preferences.
/// Both are Admin-only and both spell their rule out rather than naming it:
/// nothing else in the app creates or re-plans transactions on the user's
/// behalf, so a switch that silently does needs to say what it will produce.
struct BudgetSettingsSections: View {
    let budgetProfileID: String
    let authenticatedRESTClient: WellSpentREST.Client?

    private static let saveFallback = String(localized: "Couldn't save this setting.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)

    var body: some View {
        // Carrying a closed period's ending balance forward — see
        // docs/features/carryover-balance.md.
        BudgetSettingToggleSection(
            budgetProfileID: budgetProfileID,
            authenticatedRESTClient: authenticatedRESTClient,
            header: "Balance",
            title: "Carry balance forward",
            footer: "When a period ends, roll its balance into the next one. Money left over is added to Savings; if you overspent, the shortfall is split across the payment methods you spent it on, so the debt shows where it came from.",
            accessibilityID: "carryoverToggle",
            read: { $0.carryoverEnabled },
            write: { profileID, enabled in
                guard let authenticatedRESTClient else { return Self.saveFallback }
                do {
                    let output = try await authenticatedRESTClient.setBudgetCarryoverEnabled(.init(path: .init(id: profileID), body: .json(.init(enabled: enabled))))
                    if case .ok = output { return nil }
                    return Self.saveFallback
                } catch {
                    return RESTNetworkError.connectivityMessage(for: error) ?? Self.saveFallback
                }
            }
        )

        // Whether paying a bill differently than planned re-syncs its template
        // — amount, due date, category, and payment method. See
        // docs/features/planned-amount-follows-paid.md.
        BudgetSettingToggleSection(
            budgetProfileID: budgetProfileID,
            authenticatedRESTClient: authenticatedRESTClient,
            header: "Fixed expenses",
            title: "Keep fixed expenses in sync with reality",
            footer: "When a fixed expense is paid differently than planned, update its template for future periods: the amount actually paid, the day it was actually paid (not the original due day), and — when matching a bank transaction reveals a different one — its category and payment method. The period you're paying keeps its own values; only later ones change. Turn this off to keep your fixed expense templates exactly as you set them.",
            accessibilityID: "plannedAmountSyncToggle",
            read: { $0.autoUpdatePlannedAmount },
            write: { profileID, enabled in
                guard let authenticatedRESTClient else { return Self.saveFallback }
                do {
                    let output = try await authenticatedRESTClient.setBudgetAutoUpdatePlannedAmount(.init(path: .init(id: profileID), body: .json(.init(enabled: enabled))))
                    if case .ok = output { return nil }
                    return Self.saveFallback
                } catch {
                    return RESTNetworkError.connectivityMessage(for: error) ?? Self.saveFallback
                }
            }
        )
    }
}
