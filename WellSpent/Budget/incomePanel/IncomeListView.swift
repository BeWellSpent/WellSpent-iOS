import SwiftUI
import WellSpentAPI

struct IncomeListView: View {
    let budgetProfileID: String
    let budgetCountryCode: String
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String

    @State private var viewModel: IncomeViewModel?
    @State private var isAddSheetPresented = false
    @State private var editingSource: Wellspent_V1_IncomeSource?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Income")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addIncomeSourceButton")
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = IncomeViewModel(budgetProfileID: budgetProfileID, authenticatedClient: authenticatedClient)
            viewModel = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: IncomeViewModel) -> some View {
        List {
            if viewModel.sources.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if viewModel.sources.isEmpty {
                Text("No income sources yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.sources, id: \.id) { source in
                    sourceRow(source, viewModel: viewModel)
                }
                .onDelete { offsets in
                    for index in offsets {
                        let source = viewModel.sources[index]
                        Task { await viewModel.delete(id: source.id) }
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
            AddEditIncomeView(
                mode: .add,
                budgetProfileID: budgetProfileID,
                countryCode: budgetCountryCode,
                currencyCode: currencyCode,
                people: viewModel.people,
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
                AddEditIncomeView(
                    mode: .edit(editingSource),
                    budgetProfileID: budgetProfileID,
                    countryCode: budgetCountryCode,
                    currencyCode: currencyCode,
                    people: viewModel.people,
                    authenticatedClient: authenticatedClient
                ) { updated in
                    viewModel.replaceSource(updated)
                }
            }
        }
    }

    private func sourceRow(_ source: Wellspent_V1_IncomeSource, viewModel: IncomeViewModel) -> some View {
        Button {
            editingSource = source
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(MoneyFormatting.format(
                        units: source.defaultAmount.units,
                        nanos: source.defaultAmount.nanos,
                        currencyCode: currencyCode,
                        localeIdentifier: localeIdentifier
                    ))
                    Text("· \(RecurringTypeLabel.text(for: source.paymentFrequency))")
                    if let personName = viewModel.personName(for: source.budgetPersonID) {
                        Text("· \(personName)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("incomeRow_\(source.name)")
    }
}
