import Foundation

/// Shared "positive decimal string in a text field" <-> proto `Money`
/// units/nanos conversion, used by every add/edit form that takes a money
/// amount (income, transactions, ...). Forms that need a signed amount (e.g.
/// transactions' Spent/Received toggle) keep the sign in a separate flag and
/// pass/read only the absolute value here.
nonisolated enum MoneyInput {
    /// Parses a user-entered decimal string (e.g. "1234.56") into proto
    /// `Money`'s units/nanos fixed-point pair. `nil` for empty, non-numeric,
    /// or negative input.
    static func parseAmount(_ text: String) -> (units: Int64, nanos: Int32)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0 else { return nil }
        let units = Int64(value)
        let nanos = Int32(((value - Double(units)) * 1_000_000_000).rounded())
        return (units, nanos)
    }

    /// Formats units/nanos back into an editable decimal string. Callers
    /// with a possibly-negative amount (e.g. a Received transaction) should
    /// pass in the absolute value.
    static func formatForEditing(units: Int64, nanos: Int32) -> String {
        let value = Double(units) + Double(nanos) / 1_000_000_000
        return value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    /// Strips characters that can't be part of a valid positive decimal
    /// amount — digits and at most one decimal point. `.keyboardType(.decimalPad)`
    /// alone only restricts the on-screen keyboard, not a hardware keyboard
    /// or paste (see `AmountTextField`) — this is the actual filter;
    /// `parseAmount` still does the real parse/validate at submit time.
    /// Splits a total amount evenly across `count` parts, distributing any
    /// leftover cent to the first parts so they sum back to exactly the
    /// total (e.g. a $100 salary paid 3x/period becomes $33.34/$33.33/$33.33).
    /// Works in whole cents, not raw nanos — nanos' 1e-9 resolution is far
    /// finer than money actually displays, so dividing in cents is what
    /// keeps every part a real, displayable amount.
    static func splitEvenly(units: Int64, nanos: Int32, count: Int) -> [(units: Int64, nanos: Int32)] {
        guard count > 1 else { return [(units, nanos)] }
        let totalCents = units * 100 + Int64((Double(nanos) / 1_000_000_000 * 100).rounded())
        let base = totalCents / Int64(count)
        let remainder = Int(totalCents % Int64(count))
        return (0..<count).map { i in
            let cents = base + (i < remainder ? 1 : 0)
            return (cents / 100, Int32(cents % 100) * 10_000_000)
        }
    }

    static func sanitize(_ text: String) -> String {
        var seenDecimalPoint = false
        return text.filter { char in
            if char.isNumber { return true }
            if char == "." && !seenDecimalPoint {
                seenDecimalPoint = true
                return true
            }
            return false
        }
    }
}
