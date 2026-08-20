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

        // Whether paying a bill at a different amount re-plans future periods.
        BudgetSettingToggleSection(
            budgetProfileID: budgetProfileID,
            authenticatedClient: authenticatedClient,
            header: "Planned amounts",
            title: "Update the plan when a bill costs more",
            footer: "When you mark a bill paid at a different amount, plan future periods at that new amount. The period you're paying keeps its original plan — only later ones change. Turn this off to keep your planned amounts exactly as you set them.",
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
