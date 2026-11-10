import Foundation

/// Presentation rules for the Reports tab. Every amount is the server's; this
/// only decides what's selectable on the Free plan and how amounts read.
nonisolated enum ReportsCalculations {
    static let trendRanges = [3, 6, 12]
    /// Free sees the current period and the 3 before it, so only the 3-period range is fully open.
    static let freeMaxRange = 3

    enum ScorecardStatus: Equatable {
        case locked, inProgress, noPlan, notScored, onPlan, over
    }

    /// What one scorecard row says about its period.
    static func scorecardStatus(locked: Bool, inProgress: Bool, planRecorded: Bool, onPlan: Bool?) -> ScorecardStatus {
        if locked { return .locked }
        if inProgress { return .inProgress }
        if !planRecorded { return .noPlan }
        switch onPlan {
        case true?: return .onPlan
        case false?: return .over
        case nil: return .notScored
        }
    }

    static func isRangeLocked(_ range: Int, isPro: Bool) -> Bool {
        !isPro && range > freeMaxRange
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
