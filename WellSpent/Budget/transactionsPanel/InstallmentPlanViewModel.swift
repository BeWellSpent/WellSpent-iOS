import Foundation
import Observation
import os
import WellSpentAPI

@MainActor
@Observable
final class InstallmentPlanViewModel {
    private static let logger = AppLogger.logger("InstallmentPlan")

    private(set) var payments: Int32 = 3
    private(set) var firstPayment: Date
    private(set) var endDate: Date
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    let transaction: Wellspent_V1_Transaction
    let budgetPeriodID: String
    private let client: Wellspent_V1_BudgetServiceClient

    init(transaction: Wellspent_V1_Transaction, budgetPeriodID: String, authenticatedClient: ProtocolClient) {
        self.transaction = transaction
        self.budgetPeriodID = budgetPeriodID
        self.client = Wellspent_V1_BudgetServiceClient(client: authenticatedClient)
        // dateOnly, not .date: `date` is a DATE-only field encoded at midnight
        // UTC, so reading it raw lands a day early anywhere behind UTC.
        let purchase = transaction.hasDate ? transaction.date.dateOnly : Date()
        let first = InstallmentPlan.defaultFirstPayment(purchase: purchase)
        self.firstPayment = first
        self.endDate = InstallmentPlan.endDate(firstPayment: first, payments: 3)
    }

    var perPayment: (units: Int64, nanos: Int32) {
        InstallmentPlan.amount(
            total: (units: transaction.amount.units, nanos: transaction.amount.nanos),
            payments: payments
        )
    }

    // Explicit setters rather than `didSet` on each field: a two-way didSet
    // re-enters on every date pick and snaps the user's chosen date to the
    // nearest interval boundary — the same trap EditFixedExpenseViewModel
    // documents.
    func setPayments(_ value: Int32) {
        payments = min(max(value, InstallmentPlan.minPayments), InstallmentPlan.maxPayments)
        endDate = InstallmentPlan.endDate(firstPayment: firstPayment, payments: payments)
    }

    func setFirstPayment(_ value: Date) {
        firstPayment = value
        endDate = InstallmentPlan.endDate(firstPayment: value, payments: payments)
    }

    /// Editing the end date moves the payment count, which moves the amount —
    /// the bidirectional link the Add/Edit Fixed Expense forms already use.
    func setEndDate(_ value: Date) {
        endDate = value
        payments = min(
            max(InstallmentPlan.payments(firstPayment: firstPayment, endDate: value), InstallmentPlan.minPayments),
            InstallmentPlan.maxPayments
        )
    }

    func submit() async -> Bool {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let response = await client.createInstallmentPlan(request: .with {
            $0.transactionID = transaction.id
            $0.budgetPeriodID = budgetPeriodID
            $0.firstPaymentDate = Google_Protobuf_Timestamp(dateOnly: firstPayment)
            $0.totalPayments = payments
            $0.endDate = Google_Protobuf_Timestamp(dateOnly: endDate)
        })

        switch response.result {
        case .success:
            Self.logger.info("created installment plan transaction=\(self.transaction.id, privacy: .public) payments=\(self.payments, privacy: .public)")
            return true
        case .failure(let error):
            Self.logger.error("installment plan failed transaction=\(self.transaction.id, privacy: .public) message=\(error.message ?? "", privacy: .public)")
            errorMessage = error.message ?? String(
                localized: "Couldn't create the installment plan.",
                locale: AppLanguageStore.currentLocale
            )
            return false
        }
    }
}
