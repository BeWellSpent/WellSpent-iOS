import Foundation
import WellSpentAPI
import WellSpentREST

/// Plain values for the Reports tab. Reports have no protobuf types, and the
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
        /// Committed (commitments) or spent (trends); nil when locked.
        let amount: Wellspent_V1_Money?
        let percentOfIncome: Double?
        let categories: [CategoryAmount]
    }

    struct Drop: Equatable {
        let endsOn: Date
        let amount: Wellspent_V1_Money
        let names: [String]
    }

    struct Commitments: Equatable {
        let periods: [Period]
        let categories: [CategoryAmount]
        let incomePlanned: Wellspent_V1_Money
        let committedPercentOfIncome: Double?
        let billCount: Int
        let planCount: Int
        let projection: [Drop]?
        let projectionLocked: Bool
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

    static func commitments(from r: Components.Schemas.CommitmentReport) -> Commitments {
        Commitments(
            periods: r.periods.map {
                Period(id: $0.value1.budgetPeriodId, start: date($0.value1.startDate), locked: $0.value1.locked,
                       amount: $0.value2.committed.map(BudgetRESTMapping.money(from:)), percentOfIncome: nil, categories: [])
            },
            categories: r.categories.map(categoryAmount(from:)),
            incomePlanned: BudgetRESTMapping.money(from: r.incomePlanned),
            committedPercentOfIncome: r.committedPercentOfIncome,
            billCount: Int(r.billCount),
            planCount: Int(r.planCount),
            projection: r.projection.map { drops in
                drops.map { Drop(endsOn: date($0.endsOn), amount: BudgetRESTMapping.money(from: $0.amount), names: $0.names) }
            },
            projectionLocked: r.projectionLocked
        )
    }

    static func trends(from r: Components.Schemas.CategoryTrendsReport) -> Trends {
        Trends(
            periods: r.periods.map {
                Period(id: $0.value1.budgetPeriodId, start: date($0.value1.startDate), locked: $0.value1.locked,
                       amount: $0.value2.total.map(BudgetRESTMapping.money(from:)), percentOfIncome: $0.value2.totalPercentOfIncome,
                       categories: $0.value2.categories.map(categoryAmount(from:)))
            },
            movers: r.movers.map {
                Mover(categoryID: $0.categoryId, current: BudgetRESTMapping.money(from: $0.current), average: BudgetRESTMapping.money(from: $0.average),
                      delta: BudgetRESTMapping.money(from: $0.delta), deltaPercentOfIncome: $0.deltaPercentOfIncome)
            }
        )
    }

    private static func categoryAmount(from c: Components.Schemas.CategoryAmount) -> CategoryAmount {
        CategoryAmount(categoryID: c.categoryId, amount: BudgetRESTMapping.money(from: c.amount), percentOfIncome: c.percentOfIncome)
    }

    /// DATE-only fields, read as the local calendar day.
    private static func date(_ restDate: String) -> Date {
        Google_Protobuf_Timestamp(restDate: restDate)?.dateOnly ?? .distantPast
    }
}
