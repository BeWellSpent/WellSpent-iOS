import Foundation

/// Formats a proto `Money` value (units + nanos, base-10^9 fixed point) as a
/// localized currency string. Mirrors web's `formatMoney`/`formatMoneyFromNumber`
/// (`WellSpent-web/src/lib/format.ts`) — same units/nanos decomposition, same
/// "fall back to the raw code if the locale/currency pair can't format" idea.
nonisolated enum MoneyFormatting {
    static func format(units: Int64, nanos: Int32, currencyCode: String, localeIdentifier: String) -> String {
        let amount = Double(units) + Double(nanos) / 1_000_000_000

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.currencyCode = currencyCode

        if let formatted = formatter.string(from: NSNumber(value: amount)) {
            return formatted
        }
        // Invalid/unrecognized currency code: fall back to a plain numeric
        // string with the code appended rather than showing nothing.
        return String(format: "%.2f %@", amount, currencyCode)
    }
}
