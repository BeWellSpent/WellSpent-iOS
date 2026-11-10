import Foundation
import WellSpentAPI

/// What Plan's Fixed Expenses row says about a template that isn't an open-ended
/// bill: which kind of plan it is, how far along, and when it ends.
nonisolated enum FixedExpensePlanSummary {
    enum Kind: Equatable {
        /// A card purchase split into installments (`CreateInstallmentPlan`).
        case installments
        /// Anything else with an end date or a payment count, e.g. a loan.
        case paymentPlan
    }

    /// An end this close, in time or in payments, is worth drawing the eye to.
    static let endingSoonDays = 60
    static let endingSoonPayments = 2

    static func kind(for expense: Wellspent_V1_FixedExpense) -> Kind? {
        if expense.isInstallmentPlan { return .installments }
        if expense.hasEndDate || expense.totalPayments > 0 { return .paymentPlan }
        return nil
    }

    static func progressText(for expense: Wellspent_V1_FixedExpense) -> String? {
        guard expense.totalPayments > 0 else { return nil }
        let made = Int(expense.paymentsMade)
        let total = Int(expense.totalPayments)
        return String(localized: "\(made) / \(total) payments", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
    }

    static func endsText(for expense: Wellspent_V1_FixedExpense, localeIdentifier: String) -> String? {
        guard expense.hasEndDate else { return nil }
        let date = NextDueDateFormatting.text(expense.endDate, localeIdentifier: localeIdentifier)
        return String(localized: "Ends \(date)", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
    }

    static func isEndingSoon(_ expense: Wellspent_V1_FixedExpense, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if expense.totalPayments > 0, expense.totalPayments - expense.paymentsMade <= endingSoonPayments {
            return true
        }
        guard expense.hasEndDate else { return false }
        let end = expense.endDate.dateOnly
        guard let horizon = calendar.date(byAdding: .day, value: endingSoonDays, to: calendar.startOfDay(for: now)) else { return false }
        return end <= horizon
    }
}
