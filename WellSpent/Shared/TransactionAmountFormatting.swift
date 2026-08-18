import WellSpentAPI

/// Sign/display rules for a variable transaction's amount, matching
/// docs/features/negative-positive-transactions.md: `amount >= 0` is Spent
/// (shown with a "-" prefix), `amount < 0` is Received (shown with a "+"
/// prefix). `units` and `nanos` always carry the same sign on the wire.
nonisolated enum TransactionAmountFormatting {
    /// A received amount is simply a negative one; the name records what a
    /// negative *transaction* amount means, while `MoneyFormatting.isNegative`
    /// is the same test for money that isn't a transaction (a remainder, say).
    static func isReceived(units: Int64, nanos: Int32) -> Bool {
        MoneyFormatting.isNegative(units: units, nanos: nanos)
    }

    /// Extracts the (units, nanos) tuple every local sum/comparison helper
    /// here operates on from a proto `Money`, defaulting to zero when the
    /// field is unset (a server-computed summary response can omit a Money
    /// field entirely when the amount is exactly zero).
    static func tuple(from money: Wellspent_V1_Money?) -> (units: Int64, nanos: Int32) {
        guard let money else { return (0, 0) }
        return (money.units, money.nanos)
    }

    static func displayText(units: Int64, nanos: Int32, currencyCode: String, localeIdentifier: String) -> String {
        let prefix = isReceived(units: units, nanos: nanos) ? "+" : "-"
        let formatted = MoneyFormatting.format(
            units: abs(units),
            nanos: abs(nanos),
            currencyCode: currencyCode,
            localeIdentifier: localeIdentifier
        )
        return "\(prefix)\(formatted)"
    }

    /// Sums a list of (units, nanos) pairs, carrying any nanos overflow (or
    /// underflow, for negative amounts) into units. Shared by running totals
    /// (Variable/Fixed transaction lists) and the Expense Plan's planned-total
    /// fallback rule.
    static func sum(_ amounts: [(units: Int64, nanos: Int32)]) -> (units: Int64, nanos: Int32) {
        var units: Int64 = 0
        // Accumulated as Int64, not Int32 — each individual value's nanos is
        // bounded to +/-999,999,999, but the running total before the final
        // carry below is not, and enough entries with large fractional cents
        // (e.g. three $X.99 amounts) overflows Int32 well before the loop
        // finishes, crashing with a fatal arithmetic-overflow trap. Int64 has
        // effectively unlimited headroom for any realistic number of entries.
        var nanosTotal: Int64 = 0
        for amount in amounts {
            units += amount.units
            nanosTotal += Int64(amount.nanos)
        }
        let carried = nanosTotal / 1_000_000_000
        units += carried
        nanosTotal -= carried * 1_000_000_000
        return (units, Int32(nanosTotal))
    }

    /// Sums a list of (units, nanos) pairs and formats the result. Shared by
    /// the Variable and Fixed transaction lists' running totals.
    static func totalDisplayText(amounts: [(units: Int64, nanos: Int32)], currencyCode: String, localeIdentifier: String) -> String {
        let total = sum(amounts)
        return displayText(units: total.units, nanos: total.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
