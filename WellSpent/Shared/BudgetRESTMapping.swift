import Foundation
import WellSpentAPI
import WellSpentREST

/// Converts the Budget-domain REST schemas into the same proto messages every call site already
/// consumes. One shared file for the whole Budget cluster (profile/period, people/preferences,
/// income/savings, categories/payment methods, transactions, installment/fixed expenses,
/// allocations/expense summary, transaction review) — matches `FeatureFlags.csharpBudgetEnabled`
/// being one shared flag for the same reason.
nonisolated enum BudgetRESTMapping {
    static func profile(from p: Components.Schemas.BudgetProfile) -> Wellspent_V1_BudgetProfile {
        .with {
            $0.id = p.id
            $0.userID = p.userId
            $0.name = p.name
            $0.cycle = cycle(from: p.cycle)
            $0.countryCode = p.countryCode ?? ""
            $0.carryoverEnabled = p.carryoverEnabled
            $0.autoUpdatePlannedAmount = p.autoUpdatePlannedAmount
        }
    }

    static func cycle(from c: Components.Schemas.BudgetCycle) -> Wellspent_V1_BudgetCycle {
        switch c {
        case .weekly: return .weekly
        case .bi_weekly: return .biWeekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }

    static func restCycle(from c: Wellspent_V1_BudgetCycle) -> Components.Schemas.BudgetCycle {
        switch c {
        case .weekly: return .weekly
        case .biWeekly: return .bi_weekly
        case .yearly: return .yearly
        default: return .monthly
        }
    }

    static func period(from p: Components.Schemas.BudgetPeriod) -> Wellspent_V1_BudgetPeriod {
        .with {
            $0.id = p.id
            $0.budgetProfileID = p.budgetProfileId
            if let start = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: p.startDate) {
                $0.startDate = start
            }
            if let end = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: p.endDate) {
                $0.endDate = end
            }
            $0.isArchived = p.isArchived
        }
    }

    static func person(from p: Components.Schemas.BudgetPerson) -> Wellspent_V1_BudgetPerson {
        .with {
            $0.id = p.id
            $0.budgetProfileID = p.budgetProfileId
            $0.userName = p.userName ?? ""
            $0.userID = p.userId ?? ""
            $0.color = p.color
            $0.role = role(from: p.role)
            $0.planChartType = chartType(from: p.planChartType)
            $0.overviewChartType = chartType(from: p.overviewChartType)
            $0.manualMatchReviewEnabled = p.manualMatchReviewEnabled
            $0.focusedViewEnabled = p.focusedViewEnabled
        }
    }

    static func role(from r: Components.Schemas.BudgetPersonRole) -> Wellspent_V1_BudgetRole {
        switch r {
        case .admin: return .admin
        case .collaborator: return .collaborator
        case .viewer: return .viewer
        case .unspecified: return .unspecified
        }
    }

    static func restRole(from r: Wellspent_V1_BudgetRole) -> Components.Schemas.BudgetPersonRole {
        switch r {
        case .admin: return .admin
        case .collaborator: return .collaborator
        case .viewer: return .viewer
        default: return .unspecified
        }
    }

    /// `UpdateBudgetPersonRoleRequest.role` has no `unspecified` case — callers only ever send a real role.
    static func restSendRole(from r: Wellspent_V1_BudgetRole) -> Components.Schemas.UpdateBudgetPersonRoleRequest.rolePayload {
        switch r {
        case .collaborator: return .collaborator
        case .viewer: return .viewer
        default: return .admin
        }
    }

    static func chartType(from c: Components.Schemas.ChartType?) -> Wellspent_V1_ChartType {
        switch c {
        case .pie: return .pie
        case .bar: return .bar
        case nil: return .unspecified
        }
    }

    static func restChartType(from c: Wellspent_V1_ChartType) -> Components.Schemas.ChartType? {
        switch c {
        case .pie: return .pie
        case .bar: return .bar
        default: return nil
        }
    }

    static func money(from m: Components.Schemas.Money) -> Wellspent_V1_Money {
        .with {
            $0.units = m.units
            $0.nanos = m.nanos
            $0.currency = m.currency
        }
    }

    static func restMoney(from m: Wellspent_V1_Money) -> Components.Schemas.Money {
        .init(units: m.units, nanos: m.nanos, currency: m.currency)
    }

    static func incomeSource(from s: Components.Schemas.IncomeSource) -> Wellspent_V1_IncomeSource {
        .with {
            $0.id = s.id
            $0.budgetProfileID = s.budgetProfileId
            $0.name = s.name
            $0.incomeType = incomeType(from: s.incomeType)
            $0.defaultAmount = money(from: s.defaultAmount)
            $0.recurring = s.recurring
            $0.budgetPersonID = s.budgetPersonId
            $0.paymentFrequency = recurringType(from: s.paymentFrequency)
            $0.beforeTax = s.beforeTax
        }
    }

    static func incomeType(from t: Components.Schemas.IncomeType) -> Wellspent_V1_IncomeType {
        switch t {
        case .salary: return .salary
        case .hourly: return .hourly
        case .freelance: return .freelance
        case .contractor: return .contractor
        case .investment: return .investment
        case .interest: return .interest
        case .one_time: return .oneTime
        case .gift: return .gift
        case .other: return .other
        }
    }

    static func restIncomeType(from t: Wellspent_V1_IncomeType) -> Components.Schemas.IncomeType {
        switch t {
        case .salary: return .salary
        case .hourly: return .hourly
        case .freelance: return .freelance
        case .contractor: return .contractor
        case .investment: return .investment
        case .interest: return .interest
        case .oneTime: return .one_time
        case .gift: return .gift
        default: return .other
        }
    }

    static func recurringType(from f: Components.Schemas.RecurringFrequency) -> Wellspent_V1_RecurringType {
        switch f {
        case .unspecified: return .unspecified
        case .one_off: return .oneOff
        case .weekly: return .weekly
        case .bi_weekly: return .biWeekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }

    static func restRecurringFrequency(from f: Wellspent_V1_RecurringType) -> Components.Schemas.RecurringFrequency {
        switch f {
        case .oneOff: return .one_off
        case .weekly: return .weekly
        case .biWeekly: return .bi_weekly
        case .yearly: return .yearly
        default: return .monthly
        }
    }

    static func category(from c: Components.Schemas.Category) -> Wellspent_V1_Category {
        .with {
            $0.id = c.id
            $0.name = c.name
            $0.isSystem = c.isSystem
            $0.color = c.color
            $0.systemCategory = systemCategory(from: c.systemKey)
        }
    }

    /// Matches `category.system_key`'s snake_case values, backfilled once in migration 000054
    /// and never since renumbered — `name == "eating_out"` ↔ `.eatingOut`, etc.
    static func systemCategory(from key: String?) -> Wellspent_V1_SystemCategory {
        switch key {
        case "entertainment": return .entertainment
        case "insurance": return .insurance
        case "loan": return .loan
        case "wellness": return .wellness
        case "services": return .services
        case "subscription": return .subscription
        case "rent": return .rent
        case "travel": return .travel
        case "eating_out": return .eatingOut
        case "groceries": return .groceries
        case "baby": return .baby
        case "pet": return .pet
        case "misc": return .misc
        case "house": return .house
        case "gas": return .gas
        case "auto": return .auto
        case "savings": return .savings
        case "shopping": return .shopping
        case "family": return .family
        case "income": return .income
        case "payment": return .payment
        case "transfer": return .transfer
        case "transportation": return .transportation
        case "utilities": return .utilities
        case "debt": return .debt
        default: return .unspecified
        }
    }

    static func paymentMethod(from m: Components.Schemas.PaymentMethod) -> Wellspent_V1_PaymentMethod {
        .with {
            $0.id = m.id
            $0.name = m.name
            $0.type = paymentType(from: m._type)
            $0.budgetPersonID = m.budgetPersonId
            $0.color = m.color
            $0.alias = m.alias
        }
    }

    static func paymentType(from t: Components.Schemas.PaymentType) -> Wellspent_V1_PaymentType {
        switch t {
        case .cash: return .cash
        case .credit: return .credit
        case .debit: return .debit
        case .digital_wallet: return .digitalWallet
        case .bank_transfer: return .bankTransfer
        case .crypto: return .crypto
        case .investment: return .investment
        case .other: return .other
        case .unspecified: return .unspecified
        }
    }

    static func restPaymentType(from t: Wellspent_V1_PaymentType) -> Components.Schemas.PaymentType {
        switch t {
        case .cash: return .cash
        case .credit: return .credit
        case .debit: return .debit
        case .digitalWallet: return .digital_wallet
        case .bankTransfer: return .bank_transfer
        case .crypto: return .crypto
        case .investment: return .investment
        case .other: return .other
        default: return .unspecified
        }
    }

    static func transaction(from t: Components.Schemas.Transaction) -> Wellspent_V1_Transaction {
        .with {
            $0.id = t.id
            $0.name = t.name ?? ""
            $0.amount = money(from: t.amount)
            $0.plannedAmount = money(from: t.plannedAmount)
            if let date = t.date, let ts = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: date) {
                $0.date = ts
            }
            if let renewal = t.renewalDate, let ts = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: renewal) {
                $0.renewalDate = ts
            }
            $0.budgetPeriodID = t.budgetPeriodId ?? ""
            $0.categoryID = t.categoryId
            $0.paymentMethodID = t.paymentMethodId ?? ""
            $0.transactionFrequencyID = transactionFrequencyID(from: t.transactionFrequency)
            $0.transactionTypeID = expenseTypeID(from: t.transactionType)
            $0.isPaid = t.isPaid
            if let paidAt = t.paidAt, let ts = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: paidAt) {
                $0.paidAt = ts
            }
            $0.fixedExpenseID = t.fixedExpenseId ?? ""
            $0.isExcluded = t.isExcluded
            $0.isPlaidImported = t.isPlaidImported
            $0.installmentFixedExpenseID = t.installmentFixedExpenseId ?? ""
            $0.carriedFromBudgetPeriodID = t.carriedFromBudgetPeriodId ?? ""
        }
    }

    /// `fixedExpensePaidOffEarly` has no proto equivalent (REST-only, pay-in-full
    /// feature) — carried alongside the mapped `Transaction` rather than on it.
    static func isFixedExpensePaidOffEarly(from t: Components.Schemas.Transaction) -> Bool {
        t.fixedExpensePaidOffEarly
    }

    /// `transaction_type` lookup table seed order (migration 000001): Fixed = 1, Variable = 2.
    /// Raw int32 FK on the proto wire, unlike REST's real `ExpenseType` string enum.
    static func expenseTypeID(from t: Components.Schemas.ExpenseType) -> Int32 {
        switch t {
        case .fixed: return 1
        case .variable: return 2
        case .unspecified: return 0
        }
    }

    static func restExpenseType(from id: Int32) -> Components.Schemas.ExpenseType {
        switch id {
        case 1: return .fixed
        case 2: return .variable
        default: return .unspecified
        }
    }

    /// `transaction_frequency` lookup table seed order (migration 000001): One-off = 1,
    /// Weekly = 2, Bi-weekly = 3, Monthly = 4, Yearly = 5. Raw int32 FK on the proto wire.
    static func transactionFrequencyID(from f: Components.Schemas.RecurringFrequency) -> Int32 {
        switch f {
        case .unspecified: return 0
        case .one_off: return 1
        case .weekly: return 2
        case .bi_weekly: return 3
        case .monthly: return 4
        case .yearly: return 5
        }
    }

    static func restTransactionFrequency(from id: Int32) -> Components.Schemas.RecurringFrequency {
        switch id {
        case 1: return .one_off
        case 2: return .weekly
        case 3: return .bi_weekly
        case 4: return .monthly
        case 5: return .yearly
        default: return .unspecified
        }
    }

    static func transactionReview(from r: Components.Schemas.TransactionReview) -> Wellspent_V1_TransactionReview {
        .with {
            $0.id = r.id
            $0.budgetPeriodID = r.budgetPeriodId
            $0.transactionID = r.transactionId
            $0.matchedTransactionID = r.matchedTransactionId
            $0.matchScore = r.matchScore
            $0.status = r.status.rawValue
            $0.createdAt = SwiftProtobuf.Google_Protobuf_Timestamp(date: r.createdAt)
            $0.transactionName = r.transactionName ?? ""
            $0.transactionAmount = money(from: r.transactionAmount)
            $0.matchedTransactionName = r.matchedTransactionName ?? ""
            $0.transactionPersonID = r.transactionPersonId
            $0.matchedTransactionPersonID = r.matchedTransactionPersonId
        }
    }

    static func expenseAllocation(from a: Components.Schemas.ExpenseAllocation) -> Wellspent_V1_ExpenseAllocation {
        .with {
            $0.id = a.id
            $0.budgetProfileID = a.budgetProfileId
            $0.categoryID = a.categoryId
            $0.budgetPersonID = a.budgetPersonId
            $0.plannedAmount = money(from: a.plannedAmount)
        }
    }

    static func personExpenseSummary(from p: Components.Schemas.PersonExpenseSummary) -> Wellspent_V1_PersonExpenseSummary {
        .with {
            $0.budgetPersonID = p.budgetPersonId
            $0.plannedTotal = money(from: p.plannedTotal)
            $0.actualTotal = money(from: p.actualTotal)
        }
    }

    static func categoryExpenseSummary(from c: Components.Schemas.CategoryExpenseSummary) -> Wellspent_V1_CategoryExpenseSummary {
        .with {
            $0.categoryID = c.categoryId
            $0.plannedTotal = money(from: c.plannedTotal)
            if let actual = c.actualTotal {
                $0.actualTotal = money(from: actual)
            }
            $0.isOver = c.isOver
            $0.personBreakdowns = c.personBreakdowns.map(personExpenseSummary(from:))
            if let notDue = c.notDuePlannedTotal {
                $0.notDuePlannedTotal = money(from: notDue)
            }
            if let nextDue = c.nextDueDate, let ts = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: nextDue) {
                $0.nextDueDate = ts
            }
        }
    }

    static func expenseSummary(from s: Components.Schemas.GetExpenseSummaryResponse) -> Wellspent_V1_GetExpenseSummaryResponse {
        .with {
            $0.incomeFromSources = money(from: s.incomeFromSources)
            $0.incomeFromEntries = money(from: s.incomeFromEntries)
            $0.totalCommitted = money(from: s.totalCommitted)
            $0.totalPlanned = money(from: s.totalPlanned)
            $0.totalActual = money(from: s.totalActual)
            $0.uncategorizedActual = money(from: s.uncategorizedActual)
            $0.totalOverBudget = money(from: s.totalOverBudget)
            $0.totalUnplanned = money(from: s.totalUnplanned)
            $0.remainderPlan = money(from: s.remainderPlan)
            $0.remainderActual = money(from: s.remainderActual)
            $0.remainderPlanned = money(from: s.remainderPlanned)
            $0.planCategories = s.planCategories.map(categoryExpenseSummary(from:))
            $0.overviewCategories = s.overviewCategories.map(categoryExpenseSummary(from:))
            $0.fixedActualTotal = money(from: s.fixedActualTotal)
            $0.variableActualTotal = money(from: s.variableActualTotal)
            $0.overBudgetTransactionIds = s.overBudgetTransactionIds
            $0.totalCommittedIncludingSavings = money(from: s.totalCommittedIncludingSavings)
            $0.totalPlannedIncludingSavings = money(from: s.totalPlannedIncludingSavings)
            $0.totalActualIncludingSavings = money(from: s.totalActualIncludingSavings)
            $0.savingsPlannedTotal = money(from: s.savingsPlannedTotal)
        }
    }

    static func fixedExpense(from f: Components.Schemas.FixedExpense) -> Wellspent_V1_FixedExpense {
        .with {
            $0.id = f.id
            $0.budgetProfileID = f.budgetProfileId
            $0.name = f.name
            $0.plannedAmount = money(from: f.plannedAmount)
            $0.categoryID = f.categoryId
            $0.paymentMethodID = f.paymentMethodId ?? ""
            $0.dayOfMonth = f.dayOfMonth
            $0.isActive = f.isActive
            $0.intervalMonths = f.intervalMonths
            if let nextDue = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: f.nextDueDate) {
                $0.nextDueDate = nextDue
            }
            if let anchor = f.anchorDate, let ts = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: anchor) {
                $0.anchorDate = ts
            }
            $0.frequencyUnit = frequencyUnit(from: f.frequencyUnit)
            $0.intervalWeeks = f.intervalWeeks
            $0.dayOfWeek = f.dayOfWeek
            if let end = f.endDate, let ts = SwiftProtobuf.Google_Protobuf_Timestamp(restDate: end) {
                $0.endDate = ts
            }
            $0.totalPayments = f.totalPayments
            $0.isInstallmentPlan = f.isInstallmentPlan
            $0.paymentsMade = f.paymentsMade
        }
    }

    /// `remainingBalance`/`paidOffDate` have no proto equivalent (REST-only,
    /// pay-in-full feature) — carried alongside the mapped `FixedExpense`
    /// rather than added to the generated type.
    struct FixedExpensePayoffInfo {
        let remainingBalance: Wellspent_V1_Money
        let paidOffDate: Date?
    }

    static func fixedExpensePayoffInfo(from f: Components.Schemas.FixedExpense) -> FixedExpensePayoffInfo {
        FixedExpensePayoffInfo(
            remainingBalance: money(from: f.remainingBalance),
            paidOffDate: f.paidOffDate.flatMap { SwiftProtobuf.Google_Protobuf_Timestamp(restDate: $0)?.dateOnly }
        )
    }

    static func frequencyUnit(from u: Components.Schemas.FrequencyUnit) -> Wellspent_V1_FrequencyUnit {
        switch u {
        case .month: return .month
        case .week: return .week
        }
    }

    static func restFrequencyUnit(from u: Wellspent_V1_FrequencyUnit) -> Components.Schemas.FrequencyUnit {
        switch u {
        case .week: return .week
        default: return .month
        }
    }

    static func savingsSource(from s: Components.Schemas.SavingsSource) -> Wellspent_V1_SavingsSource {
        .with {
            $0.id = s.id
            $0.budgetProfileID = s.budgetProfileId
            $0.name = s.name
            $0.amount = money(from: s.amount)
            // `frequency` is a derived display string nothing in this app reads — SavingsFrequencyLabel
            // derives the same thing from `paymentDays.count` instead — so it's never round-tripped.
            $0.isTaxReserve = s.isTaxReserve
            $0.budgetPersonID = s.budgetPersonId
            if let federal = s.federalAmount { $0.federalAmount = money(from: federal) }
            if let state = s.stateAmount { $0.stateAmount = money(from: state) }
            $0.paymentMethodID = s.paymentMethodId ?? ""
            $0.paymentDays = s.paymentDays.map { Int32($0) }
        }
    }
}
