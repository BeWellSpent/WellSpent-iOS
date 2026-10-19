import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class AlertsViewModel {
    private(set) var isLoading = false
    private(set) var subscriptions: [Wellspent_V1_AlertSubscription] = []
    private(set) var categories: [Wellspent_V1_Category] = []
    private(set) var isFree = false
    private(set) var errorMessage: String?

    let budgetProfileID: String

    private let restClient: WellSpentREST.Client

    /// Free tier doesn't offer `new_transaction` at all (`docs/features/tiered-subscriptions.md`).
    var visibleAlertTypes: [AlertType] {
        isFree ? AlertType.all.filter { $0 != .newTransaction } : AlertType.all
    }

    /// Free tier caps active subscriptions at 2; updating an already-enabled
    /// type is always allowed even at the limit — only *enabling a new one* is blocked.
    var isAtLimit: Bool {
        isFree && subscriptions.count >= 2
    }

    init(budgetProfileID: String, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.restClient = restClient
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

        async let subs = fetchSubscriptions()
        async let user = UserRESTMapping.currentUser(restClient: restClient)
        async let categoriesResult = fetchCategories()

        if let subs = await subs {
            subscriptions = subs
        }

        if let user = await user {
            isFree = user.plan == .free
        }

        if let fetched = await categoriesResult {
            categories = fetched
        }
    }

    private func fetchCategories() async -> [Wellspent_V1_Category]? {
        guard let output = try? await restClient.listCategories(.init(query: .init(budgetProfileId: budgetProfileID))),
              case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return body.categories.map(BudgetRESTMapping.category(from:))
    }

    private func fetchSubscriptions() async -> [Wellspent_V1_AlertSubscription]? {
        do {
            let output = try await restClient.listAlertSubscriptions(.init(query: .init(budgetProfileId: budgetProfileID)))
            guard case .ok(let ok) = output, let body = try? ok.body.json else {
                errorMessage = "Couldn't load alert settings."
                return nil
            }
            return body.subscriptions.map(NotificationRESTMapping.alertSubscription(from:))
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? "Couldn't load alert settings."
            return nil
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
        let fallback = "Couldn't save that alert."
        do {
            let output = try await restClient.upsertAlertSubscription(.init(body: .json(.init(
                budgetProfileId: budgetProfileID,
                alertType: type.rawValue,
                channel: channel.rawValue,
                thresholdPct: Double(thresholdPct),
                thresholdScope: scope.rawValue,
                categoryId: Int(categoryID),
                notifyAllMembers: false
            ))))
            switch output {
            case .ok(let ok):
                guard let body = try? ok.body.json else { errorMessage = fallback; return }
                let subscription = NotificationRESTMapping.alertSubscription(from: body.subscription)
                if let index = subscriptions.firstIndex(where: { $0.alertType == type.rawValue }) {
                    subscriptions[index] = subscription
                } else {
                    subscriptions.append(subscription)
                }
            case .badRequest(let badRequest):
                errorMessage = (try? badRequest.body.json.message) ?? fallback
            case .notFound(let notFound):
                errorMessage = (try? notFound.body.json.message) ?? fallback
            default:
                errorMessage = fallback
            }
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
        }
    }

    private func delete(id: String) async {
        errorMessage = nil
        guard case .ok = try? await restClient.deleteAlertSubscription(.init(path: .init(id: id))) else {
            errorMessage = "Couldn't turn off that alert."
            return
        }
        subscriptions.removeAll { $0.id == id }
    }
}
