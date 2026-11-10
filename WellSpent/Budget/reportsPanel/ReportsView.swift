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
                Picker("Report", selection: Binding(get: { viewModel.tab }, set: { viewModel.tab = $0 })) {
                    Text("Commitments").tag(ReportsViewModel.Tab.commitments)
                    Text("Trends").tag(ReportsViewModel.Tab.trends)
                }
                .pickerStyle(.segmented)
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
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
