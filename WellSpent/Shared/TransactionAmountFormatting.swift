/// Sign/display rules for a variable transaction's amount, matching
/// docs/features/negative-positive-transactions.md: `amount >= 0` is Spent
/// (shown with a "-" prefix), `amount < 0` is Received (shown with a "+"
/// prefix). `units` and `nanos` always carry the same sign on the wire.
nonisolated enum TransactionAmountFormatting {
    static func isReceived(units: Int64, nanos: Int32) -> Bool {
        units < 0 || (units == 0 && nanos < 0)
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
}
