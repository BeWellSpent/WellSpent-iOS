import SwiftUI
import WellSpentAPI

struct SavingsListView: View {
    let budgetProfileID: String
    let periodStartDate: Date?
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool

    @State private var viewModel: SavingsViewModel?
    @State private var isAddSheetPresented = false
    @State private var editingSource: Wellspent_V1_SavingsSource?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Savings")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addSavingsButton")
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = SavingsViewModel(
                    budgetProfileID: budgetProfileID,
                    currencyCode: currencyCode,
                    localeIdentifier: localeIdentifier,
                    authenticatedClient: authenticatedClient
                )
            }
            await viewModel?.load()
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: SavingsViewModel) -> some View {
        List {
            Section {
                LabeledContent("Total", value: viewModel.totalText)
                    .accessibilityIdentifier("savingsTotal")
            }

            Section {
                if viewModel.sources.isEmpty && viewModel.isLoading {
                    ProgressView()
                } else if viewModel.sources.isEmpty {
                    Text("No savings sources yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.sources, id: \.id) { source in
                        sourceRow(source, viewModel: viewModel)
                            .swipeActions(edge: .trailing) {
                                if canEdit && !source.isTaxReserve {
                                    Button("Delete", role: .destructive) {
                                        Task { await viewModel.delete(id: source.id) }
                                    }
                                }
                            }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddSavingsSourceView(
                budgetProfileID: budgetProfileID,
                currencyCode: currencyCode,
                periodStartDate: periodStartDate,
                paymentMethods: viewModel.paymentMethods,
                authenticatedClient: authenticatedClient
            ) { source in
                viewModel.addSource(source)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingSource != nil },
            set: { if !$0 { editingSource = nil } }
        )) {
            if let editingSource {
                EditSavingsSourceView(
                    source: editingSource,
                    currencyCode: currencyCode,
                    periodStartDate: periodStartDate,
                    paymentMethods: viewModel.paymentMethods,
                    authenticatedClient: authenticatedClient
                ) { updated in
                    viewModel.replaceSource(updated)
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: Wellspent_V1_SavingsSource, viewModel: SavingsViewModel) -> some View {
        if source.isTaxReserve {
            taxReserveRow(source, viewModel: viewModel)
        } else if canEdit {
            Button {
                editingSource = source
            } label: {
                normalRow(source, viewModel: viewModel)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("savingsRow_\(source.name)")
        } else {
            normalRow(source, viewModel: viewModel)
                .accessibilityIdentifier("savingsRow_\(source.name)")
        }
    }

    private func normalRow(_ source: Wellspent_V1_SavingsSource, viewModel: SavingsViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(source.name)
                        .foregroundStyle(.primary)
                    if !source.paymentDays.isEmpty {
                        Text(source.paymentDays.map(String.init).joined(separator: ", "))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 4) {
                    if let personName = viewModel.personName(for: source.budgetPersonID) {
                        Text(personName)
                    }
                    if let methodName = viewModel.paymentMethodName(for: source.paymentMethodID) {
                        Text("· \(methodName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(displayText(source.amount))
                .foregroundStyle(.secondary)
        }
    }

    private func taxReserveRow(_ source: Wellspent_V1_SavingsSource, viewModel: SavingsViewModel) -> some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(source.name)
                    Text("Est. Tax")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                if source.hasFederalAmount || source.hasStateAmount {
                    Text(taxBreakdownText(source))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(displayText(source.amount))
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("taxReserveRow")
    }

    private func taxBreakdownText(_ source: Wellspent_V1_SavingsSource) -> String {
        var parts: [String] = []
        if source.hasFederalAmount {
            parts.append("Federal \(displayText(source.federalAmount))")
        }
        if source.hasStateAmount {
            parts.append("State \(displayText(source.stateAmount))")
        }
        return parts.joined(separator: " · ")
    }

    private func displayText(_ amount: Wellspent_V1_Money) -> String {
        MoneyFormatting.format(units: amount.units, nanos: amount.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}

#Preview {
    NavigationStack {
        SavingsListView(
            budgetProfileID: "preview-budget",
            periodStartDate: nil,
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en",
            canEdit: true
        )
    }
}
