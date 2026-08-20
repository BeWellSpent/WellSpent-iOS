import Foundation
import WellSpentAPI

/// Formats a proto `Money` value (units + nanos, base-10^9 fixed point) as a
/// localized currency string. Mirrors web's `formatMoney`/`formatMoneyFromNumber`
/// (`WellSpent-web/src/lib/format.ts`) — same units/nanos decomposition, same
/// "fall back to the raw code if the locale/currency pair can't format" idea.
nonisolated enum MoneyFormatting {
    /// Whether a units/nanos pair is below zero. Both fields carry the same
    /// sign on the wire, so `units` alone looks sufficient — it isn't: a
    /// -$0.50 amount is `units == 0, nanos == -500_000_000`, and a units-only
    /// check calls it non-negative. That mis-coloured a small negative
    /// remainder green ("you're fine") on both the Overview and the Plan tab.
    static func isNegative(units: Int64, nanos: Int32) -> Bool {
        units < 0 || (units == 0 && nanos < 0)
    }

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

extension MoneyFormatting {
    /// Whether two Money values represent different amounts.
    ///
    /// Compares units and nanos directly rather than going through a Double —
    /// the same exact-arithmetic rule the backend follows, for the same reason
    /// (see `internal/handler/convert.go`'s `moneyFromNumeric`, where a
    /// float64 intermediate produced values off by one nano).
    static func differs(_ lhs: Wellspent_V1_Money, _ rhs: Wellspent_V1_Money) -> Bool {
        lhs.units != rhs.units || lhs.nanos != rhs.nanos
    }
}
