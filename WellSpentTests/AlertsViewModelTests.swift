import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AlertsViewModel")
@MainActor
struct AlertsViewModelTests {
    private func makeViewModel() -> AlertsViewModel {
        AlertsViewModel(budgetProfileID: "profile-1", authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
    }

    private func subscription(type: AlertType) -> Wellspent_V1_AlertSubscription {
        .with { $0.id = "sub-\(type.rawValue)"; $0.alertType = type.rawValue }
    }

    @Test("visibleAlertTypes includes all four types for Pro/Lifetime users")
    func visibleAlertTypesIncludesAllForNonFree() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(subscriptions: [], isFree: false)
        #expect(viewModel.visibleAlertTypes == AlertType.all)
    }

    @Test("visibleAlertTypes excludes newTransaction for free-tier users")
    func visibleAlertTypesExcludesNewTransactionForFree() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(subscriptions: [], isFree: true)
        #expect(!viewModel.visibleAlertTypes.contains(.newTransaction))
        #expect(viewModel.visibleAlertTypes.count == 3)
    }

    @Test("isAtLimit is true only for free-tier users with 2+ subscriptions")
    func isAtLimitReflectsFreeAndCount() {
        let viewModel = makeViewModel()

        viewModel.setStateForTesting(subscriptions: [subscription(type: .periodCreated)], isFree: true)
        #expect(!viewModel.isAtLimit)

        viewModel.setStateForTesting(
            subscriptions: [subscription(type: .periodCreated), subscription(type: .reviewPending)],
            isFree: true
        )
        #expect(viewModel.isAtLimit)
    }

    @Test("Pro/Lifetime users are never at the limit regardless of subscription count")
    func nonFreeNeverAtLimit() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(
            subscriptions: [subscription(type: .periodCreated), subscription(type: .reviewPending), subscription(type: .spendingThreshold)],
            isFree: false
        )
        #expect(!viewModel.isAtLimit)
    }

    @Test("subscription(for:) finds the matching alert type")
    func subscriptionLookupMatchesAlertType() {
        let viewModel = makeViewModel()
        viewModel.setStateForTesting(subscriptions: [subscription(type: .spendingThreshold)], isFree: false)

        #expect(viewModel.subscription(for: .spendingThreshold) != nil)
        #expect(viewModel.subscription(for: .newTransaction) == nil)
    }

    private func category(id: Int32, name: String) -> Wellspent_V1_Category {
        .with { $0.id = id; $0.name = name }
    }

    @Test("resolvedCategoryID switching to budget scope always clears category")
    func resolvedCategoryIDClearsForBudgetScope() {
        let result = AlertsViewModel.resolvedCategoryID(
            forScope: .budget,
            existingCategoryID: 42,
            availableCategories: [category(id: 1, name: "Groceries")]
        )
        #expect(result == 0)
    }

    @Test("resolvedCategoryID switching to category scope keeps an already-set category")
    func resolvedCategoryIDKeepsExistingCategory() {
        let result = AlertsViewModel.resolvedCategoryID(
            forScope: .category,
            existingCategoryID: 7,
            availableCategories: [category(id: 1, name: "Groceries"), category(id: 7, name: "Shopping")]
        )
        #expect(result == 7)
    }

    @Test("resolvedCategoryID switching to category scope with nothing set defaults to the first available category")
    func resolvedCategoryIDDefaultsToFirstCategory() {
        let result = AlertsViewModel.resolvedCategoryID(
            forScope: .category,
            existingCategoryID: 0,
            availableCategories: [category(id: 3, name: "Groceries"), category(id: 9, name: "Shopping")]
        )
        #expect(result == 3)
    }

    @Test("resolvedCategoryID switching to category scope with no categories available stays 0")
    func resolvedCategoryIDStaysZeroWithNoCategories() {
        let result = AlertsViewModel.resolvedCategoryID(forScope: .category, existingCategoryID: 0, availableCategories: [])
        #expect(result == 0)
    }
}
