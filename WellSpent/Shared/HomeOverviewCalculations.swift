import Foundation

/// Pure rules behind the Home screen's cards: how far along a bar is, what
/// state each person line is in, which categories show, and how spending
/// splits into chart segments. Every amount comes from the server; this only
/// decides how it is drawn.
nonisolated enum HomeOverviewCalculations {
    typealias Amount = (units: Int64, nanos: Int32)

    /// The colour a person line's icon takes.
    enum LineStatus: Equatable {
        case neutral
        case met
        case short
        case over
    }

    /// One slice of the spending chart. `fraction` sums to 1 across all segments.
    struct Segment: Equatable {
        let id: String
        let name: String
        let colorHex: String
        let fraction: Double
    }

    struct ChartItem {
        let id: String
        let name: String
        let colorHex: String
        let amount: Amount
    }

    static let topCategoryCount = 3
    static let namedSegmentCount = 5
    static let otherSegmentID = "other"
    static let otherSegmentColorHex = "#C9CED6"

    static func decimal(_ amount: Amount) -> Decimal {
        Decimal(amount.units) + Decimal(amount.nanos) / 1_000_000_000
    }

    static func isZero(_ amount: Amount) -> Bool { amount.units == 0 && amount.nanos == 0 }

    /// `part / whole`, clamped to 0...1 for a progress bar; 0 when nothing is planned.
    static func fraction(_ part: Amount, of whole: Amount) -> Double {
        let total = decimal(whole)
        guard total > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: decimal(part) / total).doubleValue
        return min(max(ratio, 0), 1)
    }

    /// Planned minus spent: positive is what's left, negative how far over.
    static func remaining(spent: Amount, planned: Amount) -> Amount {
        TransactionAmountFormatting.sum([planned, (units: -spent.units, nanos: -spent.nanos)])
    }

    static func isOver(spent: Amount, planned: Amount) -> Bool {
        decimal(spent) > decimal(planned)
    }

    /// Saved against planned savings: met once the plan is reached, short
    /// while it isn't, neutral when nothing was planned.
    static func savedStatus(saved: Amount, planned: Amount) -> LineStatus {
        guard decimal(planned) > 0 else { return .neutral }
        return decimal(saved) >= decimal(planned) ? .met : .short
    }

    /// Income: met once everything planned has arrived, otherwise still
    /// coming (neutral, not a warning: paydays land through the period).
    static func incomeStatus(received: Amount, planned: Amount) -> LineStatus {
        guard decimal(planned) > 0 else { return .neutral }
        return decimal(received) >= decimal(planned) ? .met : .neutral
    }

    /// The first `topCategoryCount` rows, or all of them when expanded. The
    /// server already sorts by spending, so this never re-sorts.
    static func visibleRows<T>(_ rows: [T], expanded: Bool) -> [T] {
        expanded ? rows : Array(rows.prefix(topCategoryCount))
    }

    /// The biggest `namedSegmentCount` positive amounts as their own segments,
    /// everything else folded into one "Other". Refunds (a net negative
    /// category) take no space, since a share can't be negative.
    static func segments(_ items: [ChartItem], otherName: String) -> [Segment] {
        let positive = items
            .map { (item: $0, value: decimal($0.amount)) }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        let total = positive.reduce(Decimal(0)) { $0 + $1.value }
        guard total > 0 else { return [] }

        func share(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value / total).doubleValue }

        var result = positive.prefix(namedSegmentCount).map {
            Segment(id: $0.item.id, name: $0.item.name, colorHex: $0.item.colorHex, fraction: share($0.value))
        }
        let rest = positive.dropFirst(namedSegmentCount).reduce(Decimal(0)) { $0 + $1.value }
        if rest > 0 {
            result.append(Segment(id: otherSegmentID, name: otherName, colorHex: otherSegmentColorHex, fraction: share(rest)))
        }
        return result
    }
}
