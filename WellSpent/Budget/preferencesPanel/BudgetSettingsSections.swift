import SwiftUI
import WellSpentAPI

/// The budget-wide settings shown beneath the per-person chart preferences.
/// Both are Admin-only and both spell their rule out rather than naming it:
/// nothing else in the app creates or re-plans transactions on the user's
/// behalf, so a switch that silently does needs to say what it will produce.
struct BudgetSettingsSections: View {
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient?

    var body: some View {
        // Carrying a closed period's ending balance forward — see
        // docs/features/carryover-balance.md.
        BudgetSettingToggleSection(
            budgetProfileID: budgetProfileID,
            authenticatedClient: authenticatedClient,
            header: "Balance",
            title: "Carry balance forward",
            footer: "When a period ends, roll its balance into the next one. Money left over is added to Savings; if you overspent, the shortfall is split across the payment methods you spent it on, so the debt shows where it came from.",
            accessibilityID: "carryoverToggle",
            read: { $0.carryoverEnabled },
            write: { client, profileID, enabled in
                let response = await client.setBudgetCarryoverEnabled(request: .with {
                    $0.budgetProfileID = profileID
                    $0.enabled = enabled
                })
                if case .failure(let error) = response.result {
                    return error.message ?? String(
                        localized: "Couldn't save this setting.",
                        bundle: AppLanguageStore.currentBundle,
                        locale: AppLanguageStore.currentLocale
                    )
                }
                return nil
            }
        )

        // Whether paying a bill differently than planned re-syncs its template
        // — amount, due date, category, and payment method. See
        // docs/features/planned-amount-follows-paid.md.
        BudgetSettingToggleSection(
            budgetProfileID: budgetProfileID,
            authenticatedClient: authenticatedClient,
            header: "Fixed expenses",
            title: "Keep fixed expenses in sync with reality",
            footer: "When a fixed expense is paid differently than planned, update its template for future periods: the amount actually paid, the day it was actually paid (not the original due day), and — when matching a bank transaction reveals a different one — its category and payment method. The period you're paying keeps its own values; only later ones change. Turn this off to keep your fixed expense templates exactly as you set them.",
            accessibilityID: "plannedAmountSyncToggle",
            read: { $0.autoUpdatePlannedAmount },
            write: { client, profileID, enabled in
                let response = await client.setBudgetAutoUpdatePlannedAmount(request: .with {
                    $0.budgetProfileID = profileID
                    $0.enabled = enabled
                })
                if case .failure(let error) = response.result {
                    return error.message ?? String(
                        localized: "Couldn't save this setting.",
                        bundle: AppLanguageStore.currentBundle,
                        locale: AppLanguageStore.currentLocale
                    )
                }
                return nil
            }
        )
    }
}
