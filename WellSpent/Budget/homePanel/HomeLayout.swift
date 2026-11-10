import SwiftUI

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

/// The small grey heading above each group of cards.
struct HomeSectionHeader: View {
    let title: Text

    var body: some View {
        title
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One card fills the width; several scroll sideways with the next one
/// peeking in, so what's below stays visible without scrolling down.
struct CardCarousel<Item, ID: Hashable, Card: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        if items.count == 1, let only = items.first {
            card(only)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items, id: id) { item in
                        card(item)
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.86 }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}
