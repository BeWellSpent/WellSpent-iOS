import Foundation

/// Presentation rules for the Reports tab. Every amount is the server's; this
/// only decides what's selectable on the Free plan and how bars are sized.
nonisolated enum ReportsCalculations {
    static let trendRanges = [3, 6, 12]
    /// Free sees the current period and the 3 before it, so only the 3-period range is fully open.
    static let freeMaxRange = 3

    static func isRangeLocked(_ range: Int, isPro: Bool) -> Bool {
        !isPro && range > freeMaxRange
    }

    /// Each bar's height as a share of the tallest unlocked one; a locked bar
    /// shows as a fixed ghost height since its amount is unknown.
    static func barFractions(_ amounts: [(units: Int64, nanos: Int32)?], lockedHeight: Double = 0.6) -> [Double] {
        let maxValue = amounts.compactMap { $0 }.map(HomeOverviewCalculations.decimal).max() ?? 0
        return amounts.map { amount in
            guard let amount else { return lockedHeight }
            guard maxValue > 0 else { return 0 }
            return NSDecimalNumber(decimal: HomeOverviewCalculations.decimal(amount) / maxValue).doubleValue
        }
    }

    /// "41%"; one decimal under 10 so small categories don't read as 0%.
    static func percentText(_ value: Double) -> String {
        abs(value) < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value.rounded())
    }

    /// "$4.6k" above a Trends column; whole amounts under 1,000. Built by hand:
    /// compact currency notation needs iOS 18 and the app supports 17.
    static func compactMoneyText(_ amount: (units: Int64, nanos: Int32), currencyCode: String, localeIdentifier: String) -> String {
        let locale = Locale(identifier: localeIdentifier)
        let value = HomeOverviewCalculations.decimal(amount)
        guard abs(value) >= 1000 else {
            return value.formatted(.currency(code: currencyCode).precision(.fractionLength(0)).locale(locale))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        let thousands = (value / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return "\(formatter.currencySymbol ?? "")\(thousands)k"
    }

    /// A mover up means more spending: red. Down: green.
    static func isIncrease(_ delta: (units: Int64, nanos: Int32)) -> Bool {
        HomeOverviewCalculations.decimal(delta) > 0
    }
}
