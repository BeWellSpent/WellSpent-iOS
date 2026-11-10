import Foundation
import WellSpentAPI
import WellSpentREST

/// Plain values for Category trends. Reports have no protobuf types, and the
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
