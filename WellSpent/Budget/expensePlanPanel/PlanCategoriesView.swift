import SwiftUI
import WellSpentAPI

/// Plan's Categories sub-tab in Home's design language, with planned amounts
/// only: the plan card, a card per person, and a compact categories card
/// (docs/features/plan-view-redesign.md).
struct PlanCategoriesView: View {
    let viewModel: ExpensePlanViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onAllocate: (Wellspent_V1_Category) -> Void

    var body: some View {
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
                        Text(MoneyFormatting.format(units: shared.units, nanos: shared.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
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

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
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
            await viewModel.load()
        }
        .accessibilityIdentifier("planCategoriesView")
    }
}
