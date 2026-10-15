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
