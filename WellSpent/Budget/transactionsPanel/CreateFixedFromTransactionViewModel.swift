import Foundation
import Observation
import os
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class CreateFixedFromTransactionViewModel {
    private static let logger = AppLogger.logger("CreateFixedFromTransaction")

    var name: String
    private(set) var startDate: Date
    private(set) var frequencyUnit: Wellspent_V1_FrequencyUnit = .month
    private(set) var intervalMonths = 1
    private(set) var intervalWeeks = 1
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    let transaction: Wellspent_V1_Transaction
    let budgetPeriodID: String
    private let client: Wellspent_V1_BudgetServiceClient
    private let restClient: WellSpentREST.Client

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    init(transaction: Wellspent_V1_Transaction, budgetPeriodID: String, authenticatedClient: ProtocolClient, restClient: WellSpentREST.Client) {
        self.transaction = transaction
        self.budgetPeriodID = budgetPeriodID
        self.name = transaction.name
        // dateOnly, not .date: `date` is a DATE-only field at midnight UTC.
        self.startDate = transaction.hasDate ? transaction.date.dateOnly : Date()
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        self.restClient = restClient
    }

    func setStartDate(_ value: Date) {
        startDate = value
    }

    func setFrequencyUnit(_ value: Wellspent_V1_FrequencyUnit) {
        frequencyUnit = value
    }

    func setIntervalMonths(_ value: Int) {
        intervalMonths = value
    }

    func setIntervalWeeks(_ value: Int) {
        intervalWeeks = value
    }

    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let fallback = String(localized: "Couldn't create the fixed expense.", locale: AppLanguageStore.currentLocale)

        if FeatureFlags.csharpBudgetEnabled {
            do {
                let output = try await restClient.createFixedExpenseFromTransaction(.init(
                    path: .init(id: transaction.id),
                    query: .init(budgetPeriodId: budgetPeriodID),
                    body: .json(.init(
                        name: name.trimmingCharacters(in: .whitespaces),
                        anchorDate: Google_Protobuf_Timestamp(dateOnly: startDate).restDateString,
                        frequencyUnit: BudgetRESTMapping.restFrequencyUnit(from: frequencyUnit),
                        intervalMonths: Int32(intervalMonths),
                        intervalWeeks: Int32(intervalWeeks),
                        dayOfWeek: FixedExpenseScheduling.dayOfWeek(for: startDate)
                    ))
                ))
                guard case .ok = output else {
                    errorMessage = fallback
                    Self.logger.error("create fixed from transaction failed transaction=\(self.transaction.id, privacy: .public)")
                    return false
                }
                Self.logger.info("created fixed expense from transaction=\(self.transaction.id, privacy: .public)")
                return true
            } catch {
                errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
                Self.logger.error("create fixed from transaction failed transaction=\(self.transaction.id, privacy: .public) error=\(String(describing: error), privacy: .public)")
                return false
            }
        }

        let response = await client.createFixedExpenseFromTransaction(request: .with {
            $0.transactionID = transaction.id
            $0.budgetPeriodID = budgetPeriodID
            $0.name = name.trimmingCharacters(in: .whitespaces)
            $0.anchorDate = Google_Protobuf_Timestamp(dateOnly: startDate)
            $0.frequencyUnit = frequencyUnit
            $0.intervalMonths = Int32(intervalMonths)
            $0.intervalWeeks = Int32(intervalWeeks)
            $0.dayOfWeek = FixedExpenseScheduling.dayOfWeek(for: startDate)
        })

        switch response.result {
        case .success:
            Self.logger.info("created fixed expense from transaction=\(self.transaction.id, privacy: .public)")
            return true
        case .failure(let error):
            Self.logger.error("create fixed from transaction failed transaction=\(self.transaction.id, privacy: .public) message=\(error.message ?? "", privacy: .public)")
            errorMessage = error.message ?? fallback
            return false
        }
    }
}
