import Foundation
import WellSpentAPI
import WellSpentREST

/// Plain values for Category trends and the Plan scorecard. Reports have no protobuf types, and the
/// generated REST ones split each period across `value1`/`value2` (allOf), so
/// they're flattened here once rather than at every view.
nonisolated enum ReportsRESTMapping {
    struct CategoryAmount: Equatable {
        let categoryID: Int32
        let amount: Wellspent_V1_Money
        let percentOfIncome: Double?
    }

    struct Period: Equatable {
        let id: String
        let start: Date
        let locked: Bool
        /// Spent; nil when locked.
        let amount: Wellspent_V1_Money?
        let percentOfIncome: Double?
        let categories: [CategoryAmount]
        /// Money in · out · moved; nil when locked.
        var flows: Flows? = nil
    }

    struct Flows: Equatable {
        let moneyIn: Wellspent_V1_Money
        let moneyOut: Wellspent_V1_Money
        let income: Wellspent_V1_Money
        let refunds: Wellspent_V1_Money
        let transfersIn: Wellspent_V1_Money
        let spent: Wellspent_V1_Money
        let transfersOut: Wellspent_V1_Money
        let paidToCards: Wellspent_V1_Money
    }

    struct Mover: Equatable {
        let categoryID: Int32
        let current: Wellspent_V1_Money
        let average: Wellspent_V1_Money
        let delta: Wellspent_V1_Money
        let deltaPercentOfIncome: Double?
    }

    struct Trends: Equatable {
        let periods: [Period]
        let movers: [Mover]
    }

    struct ScorecardPeriod: Equatable {
        let id: String
        let start: Date
        let locked: Bool
        let inProgress: Bool
        let planRecorded: Bool
        let plannedSpending: Wellspent_V1_Money?
        let actualSpending: Wellspent_V1_Money?
        let onPlan: Bool?
        let categoriesWithin: Int?
        let categoriesPlanned: Int?
        let savingsPlanned: Wellspent_V1_Money?
        let savingsActual: Wellspent_V1_Money?
        let savingsMet: Bool?
    }

    struct ScorecardCategory: Equatable {
        let categoryID: Int32
        let planned: Wellspent_V1_Money
        let actual: Wellspent_V1_Money
    }

    struct Scorecard: Equatable {
        let periods: [ScorecardPeriod]
        let current: [ScorecardCategory]
        let onPlanCount: Int
        let scoredCount: Int
        let streak: Int
    }

    static func scorecard(from r: Components.Schemas.PlanScorecard) -> Scorecard {
        Scorecard(
            periods: r.periods.map {
                let p = $0.value1, s = $0.value2
                return ScorecardPeriod(
                    id: p.budgetPeriodId, start: date(p.startDate), locked: p.locked, inProgress: s.inProgress, planRecorded: s.planRecorded,
                    plannedSpending: s.plannedSpending.map(BudgetRESTMapping.money(from:)), actualSpending: s.actualSpending.map(BudgetRESTMapping.money(from:)),
                    onPlan: s.onPlan, categoriesWithin: s.categoriesWithin.map(Int.init), categoriesPlanned: s.categoriesPlanned.map(Int.init),
                    savingsPlanned: s.savingsPlanned.map(BudgetRESTMapping.money(from:)), savingsActual: s.savingsActual.map(BudgetRESTMapping.money(from:)),
                    savingsMet: s.savingsMet)
            },
            current: r.current.map { ScorecardCategory(categoryID: $0.categoryId, planned: BudgetRESTMapping.money(from: $0.planned), actual: BudgetRESTMapping.money(from: $0.actual)) },
            onPlanCount: Int(r.onPlanCount), scoredCount: Int(r.scoredCount), streak: Int(r.streak)
        )
    }

    static func trends(from r: Components.Schemas.CategoryTrendsReport) -> Trends {
        Trends(
            periods: r.periods.map {
                Period(id: $0.value1.budgetPeriodId, start: date($0.value1.startDate), locked: $0.value1.locked,
                       amount: $0.value2.total.map(BudgetRESTMapping.money(from:)), percentOfIncome: $0.value2.totalPercentOfIncome,
                       categories: $0.value2.categories.map(categoryAmount(from:)),
                       flows: $0.value2.flows.map(flows(from:)))
            },
            movers: r.movers.map {
                Mover(categoryID: $0.categoryId, current: BudgetRESTMapping.money(from: $0.current), average: BudgetRESTMapping.money(from: $0.average),
                      delta: BudgetRESTMapping.money(from: $0.delta), deltaPercentOfIncome: $0.deltaPercentOfIncome)
            }
        )
    }

    private static func flows(from f: Components.Schemas.FlowTotals) -> Flows {
        let m = BudgetRESTMapping.money(from:)
        return Flows(moneyIn: m(f.moneyIn), moneyOut: m(f.moneyOut), income: m(f.income), refunds: m(f.refunds),
                     transfersIn: m(f.transfersIn), spent: m(f.spent), transfersOut: m(f.transfersOut), paidToCards: m(f.paidToCards))
    }

    private static func categoryAmount(from c: Components.Schemas.CategoryAmount) -> CategoryAmount {
        CategoryAmount(categoryID: c.categoryId, amount: BudgetRESTMapping.money(from: c.amount), percentOfIncome: c.percentOfIncome)
    }

    /// DATE-only fields, read as the local calendar day.
    private static func date(_ restDate: String) -> Date {
        Google_Protobuf_Timestamp(restDate: restDate)?.dateOnly ?? .distantPast
    }
}
