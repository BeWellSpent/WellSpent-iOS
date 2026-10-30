import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Blocking screen shown when a period just cycled for real (`needsReview`)
/// — see docs/features/month-cycling-review.md. Presented as a
/// `.fullScreenCover` (not a `.sheet`): same reasoning as `VerifyEmailGateView`,
/// a swipeable presentation can be dismissed around the rule.
///
/// Shows the new period's carried-over rows directly (specific to this
/// screen), plus a link into the *real* Transactions list for the previous
/// period — which isn't archived, so it already has the right rules (swipe
/// actions, mark/unmark paid, exclude, Plaid category-only lock, merged
/// confirmed-match display) with no new logic needed here.
struct PeriodReviewGateView: View {
    @Bindable var viewModel: PeriodReviewViewModel
    let currencyCode: String
    let localeIdentifier: String
    let paymentMethods: [Wellspent_V1_PaymentMethod]
    let budgetProfileID: String
    let canEdit: Bool
    var reviewViewModel: TransactionReviewViewModel?
    let restClient: WellSpentREST.Client
    let onConfirmed: () -> Void

    @State private var editingCarriedOverTransaction: Wellspent_V1_Transaction?

    private var previousPeriodLabel: String {
        guard let previousPeriod = viewModel.previousPeriod else { return "" }
        return PeriodGrouping.label(for: previousPeriod, localeIdentifier: localeIdentifier)
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    ProgressView()
                } else if !viewModel.carriedOverTransactions.isEmpty {
                    Section("Carried over") {
                        ForEach(viewModel.carriedOverTransactions, id: \.id) { transaction in
                            Button {
                                editingCarriedOverTransaction = transaction
                            } label: {
                                row(for: transaction)
                            }
                            .accessibilityIdentifier("periodReviewCarriedOverRow_\(transaction.id)")
                        }
                    }
                }

                if let previousPeriod = viewModel.previousPeriod {
                    Section {
                        NavigationLink {
                            PeriodReviewTransactionsView(
                                budgetPeriodID: previousPeriod.id,
                                budgetProfileID: budgetProfileID,
                                authenticatedRESTClient: restClient,
                                currencyCode: currencyCode,
                                localeIdentifier: localeIdentifier,
                                canEdit: canEdit,
                                reviewViewModel: reviewViewModel
                            )
                        } label: {
                            Text("Review \(previousPeriodLabel) transactions")
                        }
                        .accessibilityIdentifier("periodReviewOpenTransactionsButton")
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
            .sheet(isPresented: Binding(
                get: { editingCarriedOverTransaction != nil },
                set: { if !$0 { editingCarriedOverTransaction = nil } }
            )) {
                if let transaction = editingCarriedOverTransaction {
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
        budgetProfileID: "profile",
        canEdit: true,
        restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1"),
        onConfirmed: {}
    )
}
