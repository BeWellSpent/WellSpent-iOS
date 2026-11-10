import os
import SwiftUI
import WellSpentAPI

/// Plan's Fixed expenses sub-tab, for maintaining the templates: recurring
/// bills, payment plans and bills not due this period. Totals and plan
/// progress are read on the Commitment tab.
struct PlanFixedExpensesView: View {
    let templatesViewModel: FixedExpenseTemplatesViewModel
    let planViewModel: ExpensePlanViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onEdit: (Wellspent_V1_FixedExpense) -> Void

    private static let logger = AppLogger.logger("ExpensePlan")

    var body: some View {
        let templates = templatesViewModel.fixedExpenses
        let dueIDs = planViewModel.dueFixedExpenseIDs
        let groups = PlanFixedGrouping.group(templates, dueIDs: dueIDs)

        List {
            if templates.isEmpty {
                Section {
                    if templatesViewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("No fixed expenses yet.").foregroundStyle(.secondary)
                    }
                }
            }

            group(Text("Recurring bills"), groups.recurring, muted: false, id: "planFixedRecurring")
            group(Text("Payment plans"), groups.plans, muted: false, id: "planFixedPlans")
            group(Text("Not due this period"), groups.notDue, muted: true, id: "planFixedNotDue")

            if let errorMessage = templatesViewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await templatesViewModel.load()
            await planViewModel.load()
        }
    }

    @ViewBuilder
    private func group(_ title: Text, _ expenses: [Wellspent_V1_FixedExpense], muted: Bool, id: String) -> some View {
        if !expenses.isEmpty {
            Section {
                ForEach(expenses, id: \.id) { expense in
                    row(expense)
                        .opacity(muted ? 0.55 : 1)
                }
            } header: {
                title
            }
            .accessibilityIdentifier(id)
        }
    }

    private func row(_ expense: Wellspent_V1_FixedExpense) -> some View {
        PlanFixedExpenseRow(
            expense: expense,
            viewModel: templatesViewModel,
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier,
            canEdit: canEdit,
            onEdit: {
                Self.logger.info("fixedExpenseRow: edit tapped for \(expense.id, privacy: .public) canEdit=\(self.canEdit, privacy: .public)")
                onEdit(expense)
            }
        )
        .swipeActions {
            if canEdit {
                Button(role: .destructive) {
                    Task { await templatesViewModel.deleteTemplate(expense) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("deleteFixedExpenseTemplate_\(expense.name)")
            }
        }
    }
}
