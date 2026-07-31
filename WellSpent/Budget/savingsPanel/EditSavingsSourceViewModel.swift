import Foundation
import Observation
import WellSpentAPI

@MainActor
@Observable
final class EditSavingsSourceViewModel {
    var name: String
    var amountText: String
    var paymentMethodID: String
    var paymentDays: [Int]

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    let sourceID: Int64
    let budgetProfileID: String
    let currencyCode: String
    let periodStartDate: Date

    private let client: Wellspent_V1_BudgetServiceClient

    /// Add requires exactly 1/2/4; Edit additionally allows 0 (no schedule
    /// yet), matching web's `EditSavingsModal` `VALID_COUNTS`.
    private static let validDayCounts: Set<Int> = [0, 1, 2, 4]

    var daysInMonth: Int {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: periodStartDate) ?? 1..<32
        return range.count
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && Self.validDayCounts.contains(paymentDays.count)
            && !isSubmitting
    }

    init(source: Wellspent_V1_SavingsSource, currencyCode: String, periodStartDate: Date?, authenticatedClient: ProtocolClient) {
        self.sourceID = source.id
        self.budgetProfileID = source.budgetProfileID
        self.currencyCode = currencyCode
        self.periodStartDate = periodStartDate ?? Date()
        self.name = source.name
        self.amountText = MoneyInput.formatForEditing(units: source.amount.units, nanos: source.amount.nanos)
        self.paymentMethodID = source.paymentMethodID
        self.paymentDays = source.paymentDays.map { Int($0) }.sorted()
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
    }

    func submit() async -> Wellspent_V1_SavingsSource? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let request = Wellspent_V1_UpdateSavingsSourceRequest.with {
            $0.id = sourceID
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
        let response = await client.updateSavingsSource(request: request)

        switch response.result {
        case .success(let message):
            return message.source
        case .failure(let error):
            errorMessage = error.message ?? "Couldn't save that savings source."
            return nil
        }
    }
}
