import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class AddSavingsSourceViewModel {
    var name = ""
    var amountText = ""
    var paymentMethodID = ""
    var paymentDays: [Int] = []

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    let budgetProfileID: String
    let currencyCode: String
    /// Reference date for computing how many days are in the month shown in
    /// the payment-days grid — the active period's start date, matching web's
    /// `activePeriodStart` (falls back to today when unavailable).
    let periodStartDate: Date

    private let client: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    private static let validDayCounts: Set<Int> = [1, 2, 4]

    var daysInMonth: Int {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: periodStartDate) ?? 1..<32
        return range.count
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !paymentMethodID.isEmpty
            && Self.validDayCounts.contains(paymentDays.count)
            && !isSubmitting
    }

    init(budgetProfileID: String, currencyCode: String, periodStartDate: Date?, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.periodStartDate = periodStartDate ?? Date()
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func submit() async -> Wellspent_V1_SavingsSource? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let fallback = "Couldn't add that savings source."
        let money = Wellspent_V1_Money.with {
            $0.units = amount.units
            $0.nanos = amount.nanos
            $0.currency = currencyCode
        }

        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.addSavingsSource(.init(
                    path: .init(id: budgetProfileID),
                    body: .json(.init(
                        name: name,
                        amount: BudgetRESTMapping.restMoney(from: money),
                        paymentMethodId: paymentMethodID,
                        paymentDays: paymentDays
                    ))
                ))
                guard case .ok(let ok) = output, let body = try? ok.body.json else {
                    errorMessage = fallback
                    return nil
                }
                return BudgetRESTMapping.savingsSource(from: body.source)
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                return nil
            }
        }

        let request = Wellspent_V1_AddSavingsSourceRequest.with {
            $0.budgetProfileID = budgetProfileID
            $0.name = name
            $0.amount = money
            $0.paymentMethodID = paymentMethodID
            $0.paymentDays = paymentDays.map { Int32($0) }
        }
        let response = await client.addSavingsSource(request: request)

        switch response.result {
        case .success(let message):
            return message.source
        case .failure(let error):
            errorMessage = error.message ?? fallback
            return nil
        }
    }
}
