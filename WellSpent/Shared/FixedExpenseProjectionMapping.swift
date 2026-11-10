import Foundation
import WellSpentAPI
import WellSpentREST

/// When the fixed baseline drops as payment plans end (`getFixedExpenseProjection`).
nonisolated enum FixedExpenseProjectionMapping {
    struct Drop: Equatable {
        let endsOn: Date
        let amount: Wellspent_V1_Money
        let names: [String]
    }

    struct Projection: Equatable {
        /// Nil when locked (Free).
        let drops: [Drop]?
        let locked: Bool
    }

    static func projection(from p: Components.Schemas.FixedExpenseProjection) -> Projection {
        Projection(
            drops: p.projection.map { drops in
                drops.map { Drop(endsOn: Google_Protobuf_Timestamp(restDate: $0.endsOn)?.dateOnly ?? .distantPast, amount: BudgetRESTMapping.money(from: $0.amount), names: $0.names) }
            },
            locked: p.locked
        )
    }
}
