import Foundation
import Observation
import WellSpentAPI

/// Orchestrates the 4-step budget setup wizard (Create -> People -> Income
/// -> Payment Methods), mirroring web's `BudgetSetupFlow.tsx`. Owns state
/// shared across steps (the created profile, the running people list each
/// later step needs for attribution) — each step's own form fields live in
/// that step's own view model (`CreateBudgetViewModel`, reused
/// `AddEditIncomeViewModel`/`AddPaymentMethodViewModel`), not lifted here.
@MainActor
@Observable
final class BudgetSetupViewModel {
    enum Step: Int, CaseIterable {
        case create
        case people
        case income
        case paymentMethods

        var title: String {
            let locale = AppLanguageStore.currentLocale
            switch self {
            case .create: return String(localized: "Create Budget", locale: locale)
            case .people: return String(localized: "Add People", locale: locale)
            case .income: return String(localized: "Add Income", locale: locale)
            case .paymentMethods: return String(localized: "Payment Methods", locale: locale)
            }
        }
    }

    private(set) var step: Step = .create
    private(set) var profile: Wellspent_V1_BudgetProfile?
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var errorMessage: String?

    private let client: Wellspent_V1_BudgetServiceClient

    init(authenticatedClient: ProtocolClient) {
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    /// Called once step 0's `CreateBudgetViewModel.submit()` succeeds.
    /// Deliberately fires the caller's `onCreated` callback here (see
    /// `BudgetSetupFlow`), not only at the very end of the wizard like web
    /// does — a mobile app can be backgrounded/killed mid-wizard far more
    /// often than a desktop browser tab, so the new budget should already be
    /// visible/reachable from the list the moment it exists, not hidden
    /// behind an unfinished wizard.
    func budgetCreated(_ profile: Wellspent_V1_BudgetProfile) async {
        self.profile = profile
        step = .people
        await loadPeople()
    }

    /// The backend auto-adds the owner as the first person on creation
    /// (confirmed in `budget_profile_service.go`'s `Create`), so this always
    /// returns at least one person once it succeeds.
    func loadPeople() async {
        guard let profile else { return }
        let response = await client.listBudgetPeople(request: .with { $0.budgetProfileID = profile.id })
        if case .success(let message) = response.result {
            people = message.people
        }
    }

    func addPerson(name: String) async {
        guard let profile else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil

        let request = Wellspent_V1_AddBudgetPeopleRequest.with {
            $0.budgetProfileID = profile.id
            $0.people = [.with { $0.userName = trimmed }]
        }
        let response = await client.addBudgetPeople(request: request)

        switch response.result {
        case .success(let message):
            people.append(contentsOf: message.people)
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't add that person."
        }
    }

    func advance() {
        guard let nextIndex = Step.allCases.firstIndex(of: step).map({ $0 + 1 }),
              nextIndex < Step.allCases.count else { return }
        step = Step.allCases[nextIndex]
    }
}
