import Observation
import os
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class BudgetDetailViewModel {
    private static let logger = AppLogger.logger("BudgetDetail")

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

    private let restClient: WellSpentREST.Client

    init(profile: Wellspent_V1_BudgetProfile, overridePeriodID: String? = nil, restClient: WellSpentREST.Client) {
        self.profile = profile
        self.overridePeriodID = overridePeriodID
        self.restClient = restClient
    }

    func loadPeriod() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let fetched = await fetchPeriods() else { return }
        periods = fetched
        currentPeriod = PeriodGrouping.resolvePeriod(fetched, overrideID: overridePeriodID)
    }

    private func fetchPeriods() async -> [Wellspent_V1_BudgetPeriod]? {
        do {
            let output = try await restClient.listBudgetPeriods(.init(path: .init(id: profile.id)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load this budget's period."
                return nil
            }
            return body.periods.map(BudgetRESTMapping.period(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load this budget's period."
            return nil
        }
    }

    /// Reloaded after the user adds one from the gate's sheet, so the "+"
    /// starts working again without leaving the screen.
    func loadPaymentMethods() async {
        if let output = try? await restClient.listPaymentMethods(.init(path: .init(id: profile.id))),
           case .ok(let ok) = output, let body = try? ok.body.json {
            paymentMethods = body.methods.map(BudgetRESTMapping.paymentMethod(from:))
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
        guard let people = await fetchPeople() else {
            Self.logger.error("loadRole: failed to fetch people for profile \(self.profile.id, privacy: .public) — leaving canEdit at its current value (\(self.canEdit, privacy: .public))")
            return
        }
        let role = BudgetRoleResolver.role(currentUserID: currentUserID, budgetOwnerUserID: profile.userID, people: people)
        canEdit = BudgetRoleResolver.canEdit(role)
        canManageUsers = BudgetRoleResolver.canManageUsers(role)
        Self.logger.info("loadRole: profile=\(self.profile.id, privacy: .public) currentUserID=\(currentUserID ?? "nil", privacy: .public) ownerUserID=\(self.profile.userID, privacy: .public) resolvedRole=\(String(describing: role), privacy: .public) canEdit=\(self.canEdit, privacy: .public)")
    }

    private func fetchPeople() async -> [Wellspent_V1_BudgetPerson]? {
        guard let output = try? await restClient.listBudgetPeople(.init(path: .init(id: profile.id))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.people.map(BudgetRESTMapping.person(from:))
    }

    func delete() async -> Bool {
        errorMessage = nil
        let fallback = "Couldn't delete that budget."

        do {
            guard case .ok = try await restClient.deleteBudgetProfile(.init(path: .init(id: profile.id))) else {
                errorMessage = fallback
                return false
            }
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return false
        }
    }
}
