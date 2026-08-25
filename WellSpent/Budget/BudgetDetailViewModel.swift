import Observation
import WellSpentAPI

@MainActor
@Observable
final class BudgetDetailViewModel {
    private(set) var profile: Wellspent_V1_BudgetProfile
    private(set) var isLoading = false
    private(set) var currentPeriod: Wellspent_V1_BudgetPeriod?
    private(set) var errorMessage: String?
    /// Default to `true` (optimistic) while `ListBudgetPeople` is still
    /// loading, mirroring web's `useBudgetRole` returning `ADMIN` before its
    /// queries resolve — avoids every gated button flashing away then back.
    private(set) var canEdit = true
    private(set) var canManageUsers = true

    /// Loaded here rather than read off the transaction list view models:
    /// the "+" that has to be gated lives in this screen's toolbar, which is
    /// the only one that actually renders (see `BudgetDetailView`'s type
    /// doc), and it's shown before either list is mounted.
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var isLoadingPaymentMethods = true

    /// True when tapping "+" must explain what's missing instead of opening
    /// the add form — see `TransactionPrerequisites`.
    var needsPaymentMethodSetup: Bool {
        TransactionPrerequisites.needsPaymentMethod(
            paymentMethods: paymentMethods,
            isLoading: isLoadingPaymentMethods
        )
    }

    /// Set when navigating in from a specific (possibly archived) period in
    /// the period list — see `PeriodListView`. `nil` means "resolve the true
    /// active period," the default. No longer `let`: the ☰ menu's period
    /// switcher writes it through `selectPeriod(id:)`, so a period change is
    /// a state change on this screen rather than a fresh push.
    private var overridePeriodID: String?

    /// Every period on this budget, newest first. Kept (rather than resolved
    /// and discarded) so the ☰ menu can offer the switcher without a second
    /// `ListBudgetPeriods` call of its own.
    private(set) var periods: [Wellspent_V1_BudgetPeriod] = []

    /// True when `currentPeriod` is archived — the record itself is frozen
    /// (see docs/features/budget-list-view-rework.md): only a Variable
    /// transaction's category can still change, and creating/deleting/
    /// marking paid/excluding are all blocked. Manage panels (Categories,
    /// Payment Methods, People, Savings/Income Sources) are unaffected,
    /// since they're profile-level, not period-level.
    var isArchivedPeriod: Bool { currentPeriod?.isArchived ?? false }

    private let client: Wellspent_V1_BudgetServiceClient

    init(profile: Wellspent_V1_BudgetProfile, overridePeriodID: String? = nil, authenticatedClient: ProtocolClient) {
        self.profile = profile
        self.overridePeriodID = overridePeriodID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func loadPeriod() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let request = Wellspent_V1_ListBudgetPeriodsRequest.with { $0.budgetProfileID = profile.id }
        let response = await client.listBudgetPeriods(request: request)

        switch response.result {
        case .success(let message):
            periods = message.periods
            currentPeriod = PeriodGrouping.resolvePeriod(message.periods, overrideID: overridePeriodID)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load this budget's period."
        }
    }

    /// Reloaded after the user adds one from the gate's sheet, so the "+"
    /// starts working again without leaving the screen.
    func loadPaymentMethods() async {
        let response = await client.listPaymentMethods(request: .with { $0.budgetProfileID = profile.id })
        if case .success(let message) = response.result {
            paymentMethods = message.methods
        }
        isLoadingPaymentMethods = false
    }

    /// Switches which period the whole screen is showing, without pushing a
    /// new one. Resolves out of the already-loaded `periods` rather than
    /// refetching — the caller only ever passes an ID that came from that
    /// same list. An unknown ID is ignored rather than blanking the screen.
    func selectPeriod(id: String) {
        guard let period = periods.first(where: { $0.id == id }) else { return }
        overridePeriodID = id
        currentPeriod = period
    }

    func applyUpdatedProfile(_ updated: Wellspent_V1_BudgetProfile) {
        profile = updated
    }

    func loadRole(currentUserID: String?) async {
        let response = await client.listBudgetPeople(request: .with { $0.budgetProfileID = profile.id })
        guard case .success(let message) = response.result else { return }
        let role = BudgetRoleResolver.role(currentUserID: currentUserID, budgetOwnerUserID: profile.userID, people: message.people)
        canEdit = BudgetRoleResolver.canEdit(role)
        canManageUsers = BudgetRoleResolver.canManageUsers(role)
    }

    func delete() async -> Bool {
        errorMessage = nil
        let request = Wellspent_V1_DeleteBudgetProfileRequest.with { $0.id = profile.id }
        let response = await client.deleteBudgetProfile(request: request)

        switch response.result {
        case .success:
            return true
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't delete that budget."
            return false
        }
    }
}
