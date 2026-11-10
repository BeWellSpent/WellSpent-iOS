import SwiftUI
import WellSpentAPI
import WellSpentREST

/// The Reports tab: Commitments and Category trends, with a person filter
/// (docs/features/reports.md). Free sees the current period and the 3 before
/// it; locked content says "Pro — coming soon".
struct ReportsView: View {
    let budgetProfileID: String
    let currencyCode: String
    let localeIdentifier: String
    let authenticatedRESTClient: WellSpentREST.Client

    @State private var viewModel: ReportsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Reports")
        .task {
            if viewModel == nil {
                viewModel = ReportsViewModel(budgetProfileID: budgetProfileID, currencyCode: currencyCode, localeIdentifier: localeIdentifier, restClient: authenticatedRESTClient)
            }
            await viewModel?.load()
        }
    }

    private func content(_ viewModel: ReportsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    planBadge(isPro: viewModel.isPro)
                }

                PillSegmentedControl(
                    options: [(ReportsViewModel.Tab.commitments, Text("Commitments")), (.trends, Text("Trends"))],
                    selection: Binding(get: { viewModel.tab }, set: { viewModel.tab = $0 })
                )
                .accessibilityIdentifier("reportsTabPicker")

                personChips(viewModel)

                switch viewModel.tab {
                case .commitments:
                    CommitmentReportView(viewModel: viewModel)
                case .trends:
                    CategoryTrendsReportView(viewModel: viewModel)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if !viewModel.isPro {
                    AdBannerView()
                        .frame(height: 50)
                        .accessibilityIdentifier("reportsAdBanner")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await viewModel.load() }
        .accessibilityIdentifier("reportsView")
    }

    /// Which plan these reports are drawn for, so locked content has a reason on screen.
    private func planBadge(isPro: Bool) -> some View {
        (isPro ? Text("Pro") : Text("Free"))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isPro ? Color.accentColor : .secondary)
            .background((isPro ? Color.accentColor : Color.secondary).opacity(0.15), in: Capsule())
            .accessibilityIdentifier("reportsPlanBadge")
    }

    private func personChips(_ viewModel: ReportsViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(Text("Everyone"), selected: viewModel.personID == nil, id: "reportsPerson_everyone") {
                    Task { await viewModel.selectPerson(nil) }
                }
                ForEach(viewModel.people, id: \.id) { person in
                    chip(Text(person.userName), selected: viewModel.personID == person.id, id: "reportsPerson_\(person.userName)") {
                        Task { await viewModel.selectPerson(person.id) }
                    }
                }
            }
        }
    }

    private func chip(_ label: Text, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// The Transactions screens' switch: a grey track with the selected option on a white pill.
struct PillSegmentedControl<Value: Hashable>: View {
    let options: [(Value, Text)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.0 == selection
                Button {
                    selection = option.0
                } label: {
                    option.1
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Shown over or instead of Pro-only content until Pro can be bought.
struct ProLockedNote: View {
    let message: Text

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                message.font(.subheadline.weight(.semibold))
                Text("Pro is coming soon").font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lock.fill").foregroundStyle(Color.accentColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque underneath, so it stays readable when laid over blurred content.
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
