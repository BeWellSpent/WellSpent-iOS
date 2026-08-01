import Foundation
import Observation
import WellSpentAPI

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

    init(budgetProfileID: String, currencyCode: String, periodStartDate: Date?, authenticatedClient: ProtocolClient) {
        self.budgetProfileID = budgetProfileID
        self.currencyCode = currencyCode
        self.periodStartDate = periodStartDate ?? Date()
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func submit() async -> Wellspent_V1_SavingsSource? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_AddSavingsSourceRequest.with {
            $0.budgetProfileID = budgetProfileID
            $0.name = name
            $0.amount = .with {
                $0.units = amount.units
                $0.nanos = amount.nanos
                $0.currency = currencyCode
            }
            $0.paymentMethodID = paymentMethodID
            $0.paymentDays = paymentDays.map { Int32($0) }
        }
        let response = await client.addSavingsSource(request: request)

        switch response.result {
        case .success(let message):
            return message.source
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't add that savings source."
            return nil
        }
    }
}
