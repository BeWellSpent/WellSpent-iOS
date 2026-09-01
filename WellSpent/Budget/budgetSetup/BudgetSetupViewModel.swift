import Foundation
import Observation
import WellSpentAPI

/// Orchestrates the budget setup wizard, mirroring web's `BudgetSetupFlow.tsx`.
///
/// Owns state shared across steps — the created profile, the running people
/// list later steps need for attribution, the payment methods the savings step
/// needs to spend from. Each step's own form fields live in that step's view
/// model (`CreateBudgetViewModel`, the reused `AddEditIncomeViewModel` /
/// `AddPaymentMethodViewModel` / `AddSavingsSourceViewModel`), not lifted here.
@MainActor
@Observable
final class BudgetSetupViewModel {
    /// Payment methods precede income deliberately: a savings source spends
    /// from a payment method, so the savings step is unusable until that one
    /// has run. Income needs neither, so it had nothing to gain from the
    /// earlier slot. Mirrors web's `setupFlow/steps.ts`.
    enum Step: Int, CaseIterable {
        case create
        case people
        case paymentMethods
        case income
        case savings

        var title: String {
            let locale = AppLanguageStore.currentLocale
            let bundle = AppLanguageStore.currentBundle
            switch self {
            case .create: return String(localized: "Create Budget", bundle: bundle, locale: locale)
            case .people: return String(localized: "Add People", bundle: bundle, locale: locale)
            case .paymentMethods: return String(localized: "Payment Methods", bundle: bundle, locale: locale)
            case .income: return String(localized: "Add Income", bundle: bundle, locale: locale)
            case .savings: return String(localized: "Add Savings", bundle: bundle, locale: locale)
            }
        }
    }

    private(set) var step: Step = .create
    private(set) var profile: Wellspent_V1_BudgetProfile?
    private(set) var people: [Wellspent_V1_BudgetPerson] = []
    private(set) var paymentMethods: [Wellspent_V1_PaymentMethod] = []
    private(set) var errorMessage: String?
    private(set) var isCancelling = false

    private let client: Wellspent_V1_BudgetServiceClient
    private let inviteClient: Wellspent_V1_InviteServiceClient

    init(authenticatedClient: ProtocolClient) {
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.inviteClient = Wellspent_V1_InviteServiceClient(client: authenticatedClient)
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

    /// Refreshed when entering the savings step rather than kept live: the
    /// payment-methods step is what populates it, and it is the only later
    /// consumer.
    func loadPaymentMethods() async {
        guard let profile else { return }
        let response = await client.listPaymentMethods(request: .with { $0.budgetProfileID = profile.id })
        if case .success(let message) = response.result {
            paymentMethods = message.methods
        }
    }

    /// Adds a person, and invites them when an email was given.
    ///
    /// The invite is sent here rather than at the end of the wizard because
    /// `SendBudgetInvite` needs the `budget_person_id` that only exists once
    /// the person is created. A failed invite is reported without undoing the
    /// person — they are on the budget either way, and the invite can be
    /// re-sent from the Invites panel.
    func addPerson(name: String, email: String, role: Wellspent_V1_BudgetRole) async {
        guard let profile else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        errorMessage = nil

        let request = Wellspent_V1_AddBudgetPeopleRequest.with {
            $0.budgetProfileID = profile.id
            $0.people = [.with { $0.userName = trimmedName }]
        }
        let response = await client.addBudgetPeople(request: request)

        switch response.result {
        case .success(let message):
            people.append(contentsOf: message.people)
            let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
            if !trimmedEmail.isEmpty, let created = message.people.first {
                await sendInvite(email: trimmedEmail, role: role, personID: created.id, profileID: profile.id)
            }
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't add that person."
        }
    }

    private func sendInvite(email: String, role: Wellspent_V1_BudgetRole, personID: Int64, profileID: String) async {
        let request = Wellspent_V1_SendBudgetInviteRequest.with {
            $0.budgetProfileID = profileID
            $0.email = email
            $0.role = role
            $0.budgetPersonID = personID
        }
        let response = await inviteClient.sendBudgetInvite(request: request)
        if case .failure(let error) = response.result {
            errorMessage = error.message ?? "The person was added, but the invitation couldn't be sent."
        }
    }

    /// Retracts the whole thing.
    ///
    /// Deleting the profile removes everything added during setup — people,
    /// income and savings all cascade from it, and the backend clears the
    /// budget's payment methods alongside, since those are the one thing with
    /// no cascade path of their own. Any invitation already emailed dies with
    /// it: `budget_invite` cascades too, so the link stops resolving.
    ///
    /// Returns true when there is nothing left to go back to.
    func cancel() async -> Bool {
        guard let profile else { return true }
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }

        let response = await client.deleteBudgetProfile(request: .with { $0.id = profile.id })
        switch response.result {
        case .success:
            self.profile = nil
            return true
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't cancel setup."
            return false
        }
    }

    func advance() {
        guard let nextIndex = Step.allCases.firstIndex(of: step).map({ $0 + 1 }),
              nextIndex < Step.allCases.count else { return }
        step = Step.allCases[nextIndex]
    }
}
