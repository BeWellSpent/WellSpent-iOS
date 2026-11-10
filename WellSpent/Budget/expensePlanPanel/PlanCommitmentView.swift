import SwiftUI
import WellSpentAPI

/// Plan's Commitment sub-tab: the whole plan once it's set up, read-only apart
/// from tapping through to edit. Plan card, people, categories, then the fixed
/// bills this period, payment plans and when they end
/// (docs/features/plan-view-redesign.md).
struct PlanCommitmentView: View {
    let viewModel: ExpensePlanViewModel
    let templatesViewModel: FixedExpenseTemplatesViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onAllocate: (Wellspent_V1_Category) -> Void
    let onEditFixedExpense: (Wellspent_V1_FixedExpense) -> Void

    var body: some View {
        let groups = PlanFixedGrouping.group(templatesViewModel.fixedExpenses, dueIDs: viewModel.dueFixedExpenseIDs)

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HomeSectionHeader(title: Text("Plan"))
                HomePlanCard(
                    income: viewModel.incomeTotal,
                    withSavings: viewModel.committedIncludingSavingsTotal,
                    withoutSavings: viewModel.committedTotal,
                    remaining: viewModel.remainderIncludingSavingsTotal,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                )

                if !viewModel.personCards.isEmpty {
                    HomeSectionHeader(title: Text("People"))
                    CardCarousel(items: viewModel.personCards, id: \.person.id) { card in
                        PlanPersonCard(person: card.person, summary: card.summary, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
                    }
                }
                if let shared = viewModel.unattributedPlanned {
                    LabeledContent {
                        Text(format(shared.units, shared.nanos))
                            .monospacedDigit()
                    } label: {
                        Text("Shared (no person)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("planSharedPlanned")
                }

                HomeSectionHeader(title: Text("Categories"))
                PlanCategoriesCard(viewModel: viewModel, currencyCode: currencyCode, localeIdentifier: localeIdentifier, canEdit: canEdit, onAllocate: onAllocate)

                HomeSectionHeader(title: Text("Fixed expenses"))
                fixedThisPeriod(groups)

                if !groups.plans.isEmpty {
                    HomeSectionHeader(title: Text("Payment plans"))
                    PlanPaymentPlansCard(plans: groups.plans, currencyCode: currencyCode, localeIdentifier: localeIdentifier, canEdit: canEdit, onEdit: onEditFixedExpense)
                }

                if !groups.plans.isEmpty || templatesViewModel.projection?.locked == true {
                    HomeSectionHeader(title: Text("Coming up"))
                    PlanComingUpCard(projection: templatesViewModel.projection, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
                }

                ForEach([viewModel.errorMessage, templatesViewModel.errorMessage].compactMap { $0 }, id: \.self) { message in
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            async let plan: Void = viewModel.load()
            async let templates: Void = templatesViewModel.load()
            _ = await (plan, templates)
        }
        .accessibilityIdentifier("planCommitmentView")
    }

    private func fixedThisPeriod(_ groups: PlanFixedGrouping.Groups) -> some View {
        let templates = templatesViewModel.fixedExpenses
        let endingSoon = groups.plans.filter { FixedExpensePlanSummary.isEndingSoon($0) }.count
        let parts: [String] = [
            PlanFixedGrouping.dueCount(templates, dueIDs: viewModel.dueFixedExpenseIDs).map {
                String(localized: "\($0) bills this period", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
            },
            String(localized: "\(groups.plans.count) payment plans", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale),
            endingSoon > 0
                ? String(localized: "\(endingSoon) ending soon", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
                : nil,
        ].compactMap { $0 }

        return HomeCard {
            Text("Fixed this period")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let total = viewModel.fixedDuePlannedTotal {
                Text(format(total.units, total.nanos))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .accessibilityIdentifier("planFixedDueTotal")
            }
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func format(_ units: Int64, _ nanos: Int32) -> String {
        MoneyFormatting.format(units: units, nanos: nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
