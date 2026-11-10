import os
import SwiftUI
import WellSpentAPI

/// Plan's Fixed expenses sub-tab: a "Fixed this period" card, then payment
/// plans, recurring bills and bills not due this period. An inset grouped
/// list, so rows keep swipe-to-delete while reading as Home's cards.
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
            Section {
                summary(groups: groups, templates: templates, dueIDs: dueIDs)
            }

            if templates.isEmpty {
                Section {
                    if templatesViewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("No fixed expenses yet.").foregroundStyle(.secondary)
                    }
                }
            }

            group(Text("Payment plans"), groups.plans, muted: false, id: "planFixedPlans")
            group(Text("Recurring bills"), groups.recurring, muted: false, id: "planFixedRecurring")
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

    private func summary(groups: PlanFixedGrouping.Groups, templates: [Wellspent_V1_FixedExpense], dueIDs: Set<String>?) -> some View {
        let endingSoon = groups.plans.filter { FixedExpensePlanSummary.isEndingSoon($0) }.count
        let parts: [String] = [
            PlanFixedGrouping.dueCount(templates, dueIDs: dueIDs).map {
                String(localized: "\($0) bills this period", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
            },
            String(localized: "\(groups.plans.count) payment plans", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale),
            endingSoon > 0
                ? String(localized: "\(endingSoon) ending soon", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
                : nil,
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Fixed this period")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let total = planViewModel.fixedDuePlannedTotal {
                Text(MoneyFormatting.format(units: total.units, nanos: total.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .accessibilityIdentifier("planFixedDueTotal")
            }
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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
