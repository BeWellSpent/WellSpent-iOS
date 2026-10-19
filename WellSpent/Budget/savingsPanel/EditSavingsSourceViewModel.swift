import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

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

    private let restClient: WellSpentREST.Client

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

    init(source: Wellspent_V1_SavingsSource, currencyCode: String, periodStartDate: Date?, restClient: WellSpentREST.Client) {
        self.sourceID = source.id
        self.budgetProfileID = source.budgetProfileID
        self.currencyCode = currencyCode
        self.periodStartDate = periodStartDate ?? Date()
        self.name = source.name
        self.amountText = MoneyInput.formatForEditing(units: source.amount.units, nanos: source.amount.nanos)
        self.paymentMethodID = source.paymentMethodID
        self.paymentDays = source.paymentDays.map { Int($0) }.sorted()
        self.restClient = restClient
    }

    func submit() async -> Wellspent_V1_SavingsSource? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let fallback = "Couldn't save that savings source."
        let money = Wellspent_V1_Money.with {
            $0.units = amount.units
            $0.nanos = amount.nanos
            $0.currency = currencyCode
        }

        do {
            let output = try await restClient.updateSavingsSource(.init(
                path: .init(id: budgetProfileID, sourceId: sourceID),
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
}
