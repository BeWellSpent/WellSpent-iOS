import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Blocking screen shown when a period just cycled for real (`needsReview`)
/// — see docs/features/month-cycling-review.md. Presented as a
/// `.fullScreenCover` (not a `.sheet`): same reasoning as `VerifyEmailGateView`,
/// a swipeable presentation can be dismissed around the rule.
struct PeriodReviewGateView: View {
    @Bindable var viewModel: PeriodReviewViewModel
    let currencyCode: String
    let localeIdentifier: String
    let paymentMethods: [Wellspent_V1_PaymentMethod]
    let restClient: WellSpentREST.Client
    let onConfirmed: () -> Void

    private enum ActiveSheet: Identifiable {
        case editCarriedOver(Wellspent_V1_Transaction)
        case markUnpaidFixedPaid(Wellspent_V1_Transaction)

        var id: String {
            switch self {
            case .editCarriedOver(let t): return "edit-\(t.id)"
            case .markUnpaidFixedPaid(let t): return "markPaid-\(t.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    private var previousPeriodLabel: String {
        guard let previousPeriod = viewModel.previousPeriod else { return "" }
        return PeriodGrouping.label(for: previousPeriod, localeIdentifier: localeIdentifier)
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    if !viewModel.carriedOverTransactions.isEmpty {
                        Section("Carried over") {
                            ForEach(viewModel.carriedOverTransactions, id: \.id) { transaction in
                                Button {
                                    activeSheet = .editCarriedOver(transaction)
                                } label: {
                                    row(for: transaction)
                                }
                                .accessibilityIdentifier("periodReviewCarriedOverRow_\(transaction.id)")
                            }
                        }
                    }

                    if !viewModel.unpaidFixedTransactions.isEmpty {
                        Section("Still unpaid from \(previousPeriodLabel)") {
                            ForEach(viewModel.unpaidFixedTransactions, id: \.id) { transaction in
                                Button {
                                    activeSheet = .markUnpaidFixedPaid(transaction)
                                } label: {
                                    row(for: transaction)
                                }
                                .accessibilityIdentifier("periodReviewUnpaidFixedRow_\(transaction.id)")
                            }
                        }
                    }

                    if viewModel.carriedOverTransactions.isEmpty && viewModel.unpaidFixedTransactions.isEmpty {
                        Text("Nothing to review.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Review new period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await viewModel.retrigger() }
                    } label: {
                        if viewModel.isRetriggering {
                            ProgressView()
                        } else {
                            Text("Recompute carried-over balances")
                        }
                    }
                    .disabled(viewModel.isRetriggering || viewModel.isConfirming)
                    .accessibilityIdentifier("retriggerPeriodReviewButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await viewModel.confirm() {
                                onConfirmed()
                            }
                        }
                    } label: {
                        if viewModel.isConfirming {
                            ProgressView()
                        } else {
                            Text("Confirm")
                        }
                    }
                    .disabled(viewModel.isConfirming || viewModel.isRetriggering)
                    .accessibilityIdentifier("confirmPeriodReviewButton")
                }
            }
            .task {
                await viewModel.load()
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .editCarriedOver(let transaction):
                    AddEditTransactionView(
                        mode: .edit(transaction),
                        budgetPeriodID: viewModel.period.id,
                        currencyCode: currencyCode,
                        categories: viewModel.categories,
                        paymentMethods: paymentMethods,
                        restClient: restClient
                    ) { updated in
                        viewModel.replaceCarriedOverTransaction(updated)
                    }
                case .markUnpaidFixedPaid(let transaction):
                    MarkAsPaidView(transaction: transaction, currencyCode: currencyCode) { amount, paidAt in
                        Task { await viewModel.markUnpaidFixedTransactionPaid(transaction, paidAmount: amount, paidAt: paidAt) }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func row(for transaction: Wellspent_V1_Transaction) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.name)
                Text(categoryName(for: transaction.categoryID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormatting.format(
                units: transaction.amount.units,
                nanos: transaction.amount.nanos,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            ))
        }
    }

    private func categoryName(for categoryID: Int32) -> String {
        viewModel.categories.first { $0.id == categoryID }?.displayName ?? ""
    }
}

#Preview {
    PeriodReviewGateView(
        viewModel: PeriodReviewViewModel(
            period: .with { $0.id = "new"; $0.needsReview = true },
            previousPeriod: .with { $0.id = "previous" },
            budgetProfileID: "profile",
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        ),
        currencyCode: "USD",
        localeIdentifier: "en_US",
        paymentMethods: [],
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
        onConfirmed: {}
    )
}
