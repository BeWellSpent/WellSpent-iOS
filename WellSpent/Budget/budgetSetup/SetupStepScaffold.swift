import SwiftUI

/// The frame every setup step shares: progress, a large heading in the
/// content (the old toolbar title was cut off), the step's cards, and its
/// primary action pinned to the bottom.
struct SetupStepScaffold<Content: View, Action: View>: View {
    let step: BudgetSetupViewModel.Step
    @ViewBuilder let content: Content
    @ViewBuilder let action: Action

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SetupProgressHeader(step: step)
                OnboardingHeading(title: Text(step.heading), subtitle: Text(step.subtitle))
                    .padding(.bottom, 6)
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .pinnedActionBar { action }
    }
}

private struct SetupProgressHeader: View {
    let step: BudgetSetupViewModel.Step

    private var total: Int { BudgetSetupViewModel.Step.allCases.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(BudgetSetupViewModel.Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color(.systemGray4))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            Text("Step \(step.rawValue + 1) of \(total) · \(step.title)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// A card listing what this step has added so far, one row each.
struct SetupAddedList<Item, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                row(item)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Name over a secondary line, the shape of every "added so far" row.
struct SetupRowText: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title).font(.subheadline.weight(.semibold))
            if !detail.isEmpty {
                Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// The "Add …" button under each step's form, with its spinner.
struct SetupAddButton: View {
    let title: Text
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isWorking {
                ProgressView()
            } else {
                Label { title } icon: { Image(systemName: "plus") }
            }
        }
        .buttonStyle(TintedActionButtonStyle())
    }
}
