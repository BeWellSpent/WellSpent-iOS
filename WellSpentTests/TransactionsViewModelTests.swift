import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

/// Covers the payment/variable partition logic (issue #76). The RPC itself
/// is an unreachable client (`http://localhost:1`, the convention here) —
/// these exercise `setStateForTesting`-seeded state, not the network call.
@Suite("TransactionsViewModel")
@MainActor
struct TransactionsViewModelTests {
    private func makeViewModel() -> TransactionsViewModel {
        TransactionsViewModel(
            budgetPeriodID: "period-1",
            budgetProfileID: "budget-1",
            currencyCode: "USD",
            localeIdentifier: "en",
            currentUserID: nil,
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private let paymentCategory = Wellspent_V1_Category.with {
        $0.id = 1
        $0.name = "Payment"
        $0.isSystem = true
        $0.systemCategory = .payment
    }

    private let groceriesCategory = Wellspent_V1_Category.with {
        $0.id = 2
        $0.name = "Groceries"
    }

    private func tx(id: String, categoryID: Int32, units: Int64 = 10) -> Wellspent_V1_Transaction {
        .with {
            $0.id = id
            $0.categoryID = categoryID
            $0.amount = .with { $0.units = units; $0.currency = "USD" }
        }
    }

    @Test("a card-payment row is excluded from the Variable list")
    func visibleTransactionsExcludesPayments() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(
            transactions: [tx(id: "a", categoryID: paymentCategory.id), tx(id: "b", categoryID: groceriesCategory.id)],
            categories: [paymentCategory, groceriesCategory]
        )
        #expect(viewModel.visibleTransactions(reviews: []).map(\.id) == ["b"])
    }

    @Test("a card-payment row is included in the Payments bucket")
    func paymentTransactionsIncludesOnlyPayments() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(
            transactions: [tx(id: "a", categoryID: paymentCategory.id), tx(id: "b", categoryID: groceriesCategory.id)],
            categories: [paymentCategory, groceriesCategory]
        )
        #expect(viewModel.paymentTransactions(reviews: []).map(\.id) == ["a"])
    }

    @Test("with no Payment category resolvable, nothing is carved out of Variable")
    func noPaymentCategoryLeavesEverythingInVariable() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(
            transactions: [tx(id: "a", categoryID: 0), tx(id: "b", categoryID: groceriesCategory.id)],
            categories: [groceriesCategory]
        )
        #expect(viewModel.visibleTransactions(reviews: []).map(\.id) == ["a", "b"])
        #expect(viewModel.paymentTransactions(reviews: []).isEmpty)
    }

    @Test("paymentsTotalText sums only the payment rows")
    func paymentsTotalSumsCorrectly() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(
            transactions: [
                tx(id: "a", categoryID: paymentCategory.id, units: 30),
                tx(id: "b", categoryID: paymentCategory.id, units: 20),
                tx(id: "c", categoryID: groceriesCategory.id, units: 999),
            ],
            categories: [paymentCategory, groceriesCategory]
        )
        #expect(viewModel.paymentsTotalText(reviews: []) == "-$50.00")
    }
}
