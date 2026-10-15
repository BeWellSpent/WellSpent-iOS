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
}
