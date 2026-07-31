import SwiftUI
import WellSpentAPI

struct TransactionsListView: View {
    let budgetPeriodID: String
    let budgetProfileID: String
    let authenticatedClient: ProtocolClient
    let currencyCode: String
    let localeIdentifier: String

    @State private var viewModel: TransactionsViewModel?
    @State private var isAddSheetPresented = false
    @State private var editingTransaction: Wellspent_V1_Transaction?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addTransactionButton")
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = TransactionsViewModel(
                budgetPeriodID: budgetPeriodID,
                budgetProfileID: budgetProfileID,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier,
                authenticatedClient: authenticatedClient
            )
            viewModel = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: TransactionsViewModel) -> some View {
        List {
            Section {
                LabeledContent("Total", value: viewModel.totalText)
                    .accessibilityIdentifier("transactionsTotal")
            }

            if viewModel.transactions.isEmpty && viewModel.isLoading {
                ProgressView()
            } else if viewModel.transactions.isEmpty {
                Text("No transactions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.transactions, id: \.id) { transaction in
                    transactionRow(transaction, viewModel: viewModel)
                }
                .onDelete { offsets in
                    for index in offsets {
                        let transaction = viewModel.transactions[index]
                        Task { await viewModel.delete(id: transaction.id) }
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
            AddEditTransactionView(
                mode: .add,
                budgetPeriodID: budgetPeriodID,
                currencyCode: currencyCode,
                categories: viewModel.categories,
                paymentMethods: viewModel.paymentMethods,
                authenticatedClient: authenticatedClient
            ) { transaction in
                viewModel.addTransaction(transaction)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingTransaction != nil },
            set: { if !$0 { editingTransaction = nil } }
        )) {
            if let editingTransaction {
                AddEditTransactionView(
                    mode: .edit(editingTransaction),
                    budgetPeriodID: budgetPeriodID,
                    currencyCode: currencyCode,
                    categories: viewModel.categories,
                    paymentMethods: viewModel.paymentMethods,
                    authenticatedClient: authenticatedClient
                ) { updated in
                    viewModel.replaceTransaction(updated)
                }
            }
        }
    }

    private func transactionRow(_ transaction: Wellspent_V1_Transaction, viewModel: TransactionsViewModel) -> some View {
        let isReceived = TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos)

        return HStack {
            Button {
                editingTransaction = transaction
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.name)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        if let categoryName = viewModel.categoryName(for: transaction.categoryID) {
                            Text(categoryName)
                        }
                        if let methodName = viewModel.paymentMethodName(for: transaction.paymentMethodID) {
                            Text("· \(methodName)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("transactionRow_\(transaction.name)")

            Spacer()

            Text(TransactionAmountFormatting.displayText(
                units: transaction.amount.units,
                nanos: transaction.amount.nanos,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            ))
            .foregroundStyle(isReceived ? .green : .red)

            Button {
                Task { await viewModel.toggleExcluded(transaction) }
            } label: {
                Image(systemName: transaction.isExcluded ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("excludeTransaction_\(transaction.name)")
        }
    }
}

#Preview {
    NavigationStack {
        TransactionsListView(
            budgetPeriodID: "preview-period",
            budgetProfileID: "preview-budget",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
            currencyCode: "USD",
            localeIdentifier: "en"
        )
    }
}
