import Observation
import WellSpentAPI

@MainActor
@Observable
final class AlertsViewModel {
    private(set) var isLoading = false
    private(set) var subscriptions: [Wellspent_V1_AlertSubscription] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var isFree = false
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let notificationClient: Wellspent_V1_NotificationServiceClient
    private let userClient: Wellspent_V1_UserServiceClient
    private let budgetClient: Wellspent_V1_BudgetServiceClient

    /// Free tier doesn't offer `new_transaction` at all (`docs/features/tiered-subscriptions.md`).
    var visibleAlertTypes: [AlertType] {
        isFree ? AlertType.all.filter { $0 != .newTransaction } : AlertType.all
    }

    /// Free tier caps active subscriptions at 2; updating an already-enabled
    /// type is always allowed even at the limit — only *enabling a new one* is blocked.
    var isAtLimit: Bool {
        isFree && subscriptions.count >= 2
    }

    init(budgetProfileID: String, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.notificationClient = Wellspent_V1_NotificationServiceClient(client: authenticatedClient)
        self.userClient = Wellspent_V1_UserServiceClient(client: authenticatedClient)
        self.budgetClient = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    /// Not private, so `visibleAlertTypes`/`isAtLimit` are testable without a
    /// live `ListAlertSubscriptions`/`GetMe` call.
    func setStateForTesting(subscriptions: [Wellspent_V1_AlertSubscription], isFree: Bool) {
        self.subscriptions = subscriptions
        self.isFree = isFree
    }

    func subscription(for type: AlertType) -> Wellspent_V1_AlertSubscription? {
        subscriptions.first { $0.alertType == type.rawValue }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let subsResponse = notificationClient.listAlertSubscriptions(request: .with { $0.budgetProfileID = budgetProfileID })
        async let meResponse = userClient.getMe(request: Wellspent_V1_GetMeRequest())
        async let categoriesResponse = budgetClient.listCategories(request: .with { $0.budgetProfileID = budgetProfileID })

        switch await subsResponse.result {
        case .success(let message):
            subscriptions = message.subscriptions
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't load alert settings."
        }

        if case .success(let message) = await meResponse.result {
            isFree = message.user.plan == .free
        }

        if case .success(let message) = await categoriesResponse.result {
            categories = message.categories
        }
    }

    func toggle(_ type: AlertType, on: Bool) async {
        if on {
            await upsert(type, channel: .inApp, thresholdPct: type == .spendingThreshold ? 80 : 0, scope: .budget, categoryID: 0)
        } else if let existing = subscription(for: type) {
            await delete(id: existing.id)
        }
    }

    func updateChannel(_ type: AlertType, channel: AlertChannel) async {
        guard let existing = subscription(for: type) else { return }
        await upsert(
            type,
            channel: channel,
            thresholdPct: existing.thresholdPct,
            scope: ThresholdScope(rawValue: existing.thresholdScope) ?? .budget,
            categoryID: existing.categoryID
        )
    }

    func updateThreshold(_ type: AlertType, pct: Float) async {
        guard let existing = subscription(for: type) else { return }
        await upsert(
            type,
            channel: AlertChannel(rawValue: existing.channel) ?? .inApp,
            thresholdPct: pct,
            scope: ThresholdScope(rawValue: existing.thresholdScope) ?? .budget,
            categoryID: existing.categoryID
        )
    }

    /// A category scope with no category picked never fires server-side, so default to the first one.
    static func resolvedCategoryID(forScope scope: ThresholdScope, existingCategoryID: Int32, availableCategories: [Wellspent_V1_Category]) -> Int32 {
        guard scope == .category else { return 0 }
        return existingCategoryID != 0 ? existingCategoryID : (availableCategories.first?.id ?? 0)
    }

    func updateScope(_ type: AlertType, scope: ThresholdScope) async {
        guard let existing = subscription(for: type) else { return }
        let categoryID = Self.resolvedCategoryID(forScope: scope, existingCategoryID: existing.categoryID, availableCategories: categories)
        await upsert(
            type,
            channel: AlertChannel(rawValue: existing.channel) ?? .inApp,
            thresholdPct: existing.thresholdPct,
            scope: scope,
            categoryID: categoryID
        )
    }

    func updateCategory(_ type: AlertType, categoryID: Int32) async {
        guard let existing = subscription(for: type) else { return }
        await upsert(
            type,
            channel: AlertChannel(rawValue: existing.channel) ?? .inApp,
            thresholdPct: existing.thresholdPct,
            scope: ThresholdScope(rawValue: existing.thresholdScope) ?? .budget,
            categoryID: categoryID
        )
    }

    private func upsert(_ type: AlertType, channel: AlertChannel, thresholdPct: Float, scope: ThresholdScope, categoryID: Int32) async {
        errorMessage = nil
        let response = await notificationClient.upsertAlertSubscription(request: .with {
            $0.budgetProfileID = budgetProfileID
            $0.alertType = type.rawValue
            $0.channel = channel.rawValue
            $0.thresholdPct = thresholdPct
            $0.thresholdScope = scope.rawValue
            $0.categoryID = categoryID
        })

        switch response.result {
        case .success(let message):
            if let index = subscriptions.firstIndex(where: { $0.alertType == type.rawValue }) {
                subscriptions[index] = message.subscription
            } else {
                subscriptions.append(message.subscription)
            }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't save that alert."
        }
    }

    private func delete(id: String) async {
        errorMessage = nil
        let response = await notificationClient.deleteAlertSubscription(request: .with { $0.id = id })

        switch response.result {
        case .success:
            subscriptions.removeAll { $0.id == id }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't turn off that alert."
        }
    }
}
