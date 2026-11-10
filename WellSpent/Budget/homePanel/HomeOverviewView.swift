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
                sectionHeader(Text("Plan"))
                HomePlanCard(viewModel: viewModel, currencyCode: currencyCode, localeIdentifier: localeIdentifier)

                if !viewModel.personCards.isEmpty {
                    sectionHeader(Text("People"))
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

                sectionHeader(Text("Categories"))
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

    /// One person fills the width; several scroll sideways with the next one
    /// peeking in, so Categories stays visible without scrolling down.
    @ViewBuilder
    private var peopleCards: some View {
        let cards = viewModel.personCards
        if cards.count == 1, let only = cards.first {
            HomePersonCard(person: only.person, summary: only.summary, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(cards, id: \.person.id) { card in
                        HomePersonCard(person: card.person, summary: card.summary, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.86 }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// White rounded card on the grouped background, the Transactions summary card's look.
struct HomeCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
