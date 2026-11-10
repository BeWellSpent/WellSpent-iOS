import SwiftUI
import WellSpentAPI
import WellSpentREST

/// The Home tab's Overview sub-tab: the plan, one card per person, and a
/// compact categories card, as one scrolling page (docs/features/home-view-redesign.md).
///
/// Doesn't own the view model's lifecycle — `BudgetDetailView` creates and
/// loads one `ExpenseOverviewViewModel` per visit; this view only refreshes it.
struct HomeOverviewView: View {
    let viewModel: ExpenseOverviewViewModel
    let currencyCode: String
    let localeIdentifier: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HomeSectionHeader(title: Text("Plan"))
                HomePlanCard(
                    income: viewModel.plannedIncome,
                    withSavings: viewModel.plannedExpensesIncludingSavings,
                    withoutSavings: viewModel.plannedExpenses,
                    remaining: viewModel.remainingPlan,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier
                )

                if !viewModel.personCards.isEmpty {
                    HomeSectionHeader(title: Text("People"))
                    peopleCards
                }
                if let unattributed = viewModel.unattributedSpentAmount {
                    LabeledContent {
                        Text(OverviewAmountFormatting.text(unattributed, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
                    } label: {
                        Text("Unattributed")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("homeUnattributedSpent")
                }

                HomeSectionHeader(title: Text("Categories"))
                HomeCategoriesCard(viewModel: viewModel, currencyCode: currencyCode, localeIdentifier: localeIdentifier)

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
        .accessibilityIdentifier("homeOverview")
    }

    private var peopleCards: some View {
        CardCarousel(items: viewModel.personCards, id: \.person.id) { card in
            HomePersonCard(person: card.person, summary: card.summary, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
        }
    }
}
