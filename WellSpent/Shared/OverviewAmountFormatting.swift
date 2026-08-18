import WellSpentAPI

/// Amount display for the Expense Overview tab.
///
/// The Overview is an actual-vs-planned report, so spending reads as a
/// positive magnitude here — deliberately unlike the Transactions tab, where
/// `TransactionAmountFormatting.displayText` renders the same spend as `-$X`.
/// Its planned caption and its chart are magnitudes too, and negating only
/// the actual would print "-$100 of $150 planned".
///
/// What the two tabs *must* agree on is money **in**: a category whose
/// transactions net negative is money received, and it renders `+$X` on both.
/// Before this it rendered as a bare `-$X` here, so a refund read as negative
/// on one tab and positive on the other (issue #52).
///
/// Mirrors web's `formatOverviewAmountText`
/// (`expenseOverviewPanel/helpers.ts`), with one deliberate difference: web
/// renders an exact zero as an em dash and this does not, because the iOS
/// rows have always shown `$0.00` there and changing that is unrelated to the
/// sign problem.
///
/// Deliberately NOT used for the "Remaining" rows: a negative remainder means
/// spending past income, not money received, and a `+` prefix would say the
/// opposite of what it means.
nonisolated enum OverviewAmountFormatting {
    /// What an actual-spend amount is saying, independent of how the view
    /// paints it. Abstract rather than a `Color` so this file stays pure and
    /// testable without importing SwiftUI.
    enum Tone {
        case received
        case over
        case withinPlan
        case unplanned
        case zero
    }

    /// Three states for spending, so green means exactly one thing —
    /// "inside a plan you set".
    ///
    /// The `unplanned` case is the one worth stating. `isOver` is
    /// `planned > 0 && actual > planned` server-side, so a category with no
    /// plan can never be "over": it used to fall through to the default and,
    /// on web, was painted green — reading as within budget while the same
    /// money was counted into the orange Unplanned total at the bottom of the
    /// same screen. Unplanned spending is not a success.
    ///
    /// Mirrors web's `overviewActualColor` (`expenseOverviewPanel/helpers.ts`).
    /// The two return different things — an MUI token there, a tone here —
    /// but the branch order is the contract and must stay identical.
    static func tone(
        actual: (units: Int64, nanos: Int32),
        planned: (units: Int64, nanos: Int32),
        isOver: Bool
    ) -> Tone {
        if TransactionAmountFormatting.isReceived(units: actual.units, nanos: actual.nanos) {
            return .received
        }
        if actual.units == 0 && actual.nanos == 0 {
            return .zero
        }
        if isOver {
            return .over
        }
        return (planned.units > 0 || planned.nanos > 0) ? .withinPlan : .unplanned
    }

    static func text(
        _ amount: (units: Int64, nanos: Int32),
        currencyCode: String,
        localeIdentifier: String
    ) -> String {
        guard TransactionAmountFormatting.isReceived(units: amount.units, nanos: amount.nanos) else {
            return MoneyFormatting.format(
                units: amount.units,
                nanos: amount.nanos,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            )
        }
        let formatted = MoneyFormatting.format(
            units: abs(amount.units),
            nanos: abs(amount.nanos),
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
        return "+\(formatted)"
    }
}
