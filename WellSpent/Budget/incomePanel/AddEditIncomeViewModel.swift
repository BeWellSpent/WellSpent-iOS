import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class AddEditIncomeViewModel {
    enum Mode {
        case add
        case edit(Wellspent_V1_IncomeSource)
    }

    var name: String
    var incomeType: Wellspent_V1_IncomeType
    var amountText: String
    var recurring: Bool
    var personID: Int64
    var paymentFrequency: Wellspent_V1_RecurringType
    var beforeTax: Bool

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    let mode: Mode
    let countryCode: String

    private let budgetProfileID: String
    private let currencyCode: String
    private let client: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    /// Matches the backend's `before_tax_income` country feature flag — only
    /// meaningful for US users (see docs/specs/03-data-model.md).
    var showBeforeTaxToggle: Bool {
        countryCode == "US"
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !isSubmitting
    }

    init(mode: Mode, budgetProfileID: String, countryCode: String, currencyCode: String, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.mode = mode
        self.budgetProfileID = budgetProfileID
        self.countryCode = countryCode
        self.currencyCode = currencyCode
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient

        switch mode {
        case .add:
            name = ""
            incomeType = .salary
            amountText = ""
            recurring = true
            personID = 0
            paymentFrequency = .monthly
            beforeTax = false
        case .edit(let source):
            name = source.name
            incomeType = source.incomeType
            amountText = MoneyInput.formatForEditing(units: source.defaultAmount.units, nanos: source.defaultAmount.nanos)
            recurring = source.recurring
            personID = source.budgetPersonID
            paymentFrequency = source.paymentFrequency
            beforeTax = source.beforeTax
        }
    }

    func submit() async -> Wellspent_V1_IncomeSource? {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let money = Wellspent_V1_Money.with {
            $0.units = amount.units
            $0.nanos = amount.nanos
            $0.currency = currencyCode
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let applyBeforeTax = showBeforeTaxToggle && beforeTax

        switch mode {
        case .add:
            let fallback = "Couldn't add that income source."
            if FeatureFlags.csharpBudgetEnabled {
                do {
                    let output = try await restClient.addIncomeSource(.init(
                        path: .init(id: budgetProfileID),
                        body: .json(.init(
                            name: trimmedName,
                            incomeType: BudgetRESTMapping.restIncomeType(from: incomeType),
                            defaultAmount: BudgetRESTMapping.restMoney(from: money),
                            recurring: recurring,
                            budgetPersonId: personID,
                            paymentFrequency: BudgetRESTMapping.restRecurringFrequency(from: paymentFrequency),
                            beforeTax: applyBeforeTax
                        ))
                    ))
                    guard case .ok(let ok) = output, let body = try? ok.body.json else {
                        errorMessage = fallback
                        return nil
                    }
                    return BudgetRESTMapping.incomeSource(from: body.source)
                } catch {
                    errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                    return nil
                }
            }

            let request = Wellspent_V1_AddIncomeSourceRequest.with {
                $0.budgetProfileID = budgetProfileID
                $0.name = trimmedName
                $0.incomeType = incomeType
                $0.defaultAmount = money
                $0.recurring = recurring
                $0.budgetPersonID = personID
                $0.paymentFrequency = paymentFrequency
                $0.beforeTax = applyBeforeTax
            }
            let response = await client.addIncomeSource(request: request)
            switch response.result {
            case .success(let message):
                return message.source
            case .failure(let error):
                errorMessage = error.message ?? fallback
                return nil
            }
        case .edit(let existing):
            let fallback = "Couldn't update that income source."
            if FeatureFlags.csharpBudgetEnabled {
                do {
                    let output = try await restClient.updateIncomeSource(.init(
                        path: .init(id: budgetProfileID, sourceId: existing.id),
                        body: .json(.init(
                            name: trimmedName,
                            incomeType: BudgetRESTMapping.restIncomeType(from: incomeType),
                            defaultAmount: BudgetRESTMapping.restMoney(from: money),
                            recurring: recurring,
                            budgetPersonId: personID,
                            paymentFrequency: BudgetRESTMapping.restRecurringFrequency(from: paymentFrequency),
                            beforeTax: applyBeforeTax
                        ))
                    ))
                    guard case .ok(let ok) = output, let body = try? ok.body.json else {
                        errorMessage = fallback
                        return nil
                    }
                    return BudgetRESTMapping.incomeSource(from: body.source)
                } catch {
                    errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                    return nil
                }
            }

            let request = Wellspent_V1_UpdateIncomeSourceRequest.with {
                $0.id = existing.id
                $0.budgetProfileID = budgetProfileID
                $0.name = trimmedName
                $0.incomeType = incomeType
                $0.defaultAmount = money
                $0.recurring = recurring
                $0.budgetPersonID = personID
                $0.paymentFrequency = paymentFrequency
                $0.beforeTax = applyBeforeTax
            }
            let response = await client.updateIncomeSource(request: request)
            switch response.result {
            case .success(let message):
                return message.source
            case .failure(let error):
                errorMessage = error.message ?? fallback
                return nil
            }
        }
    }

}
