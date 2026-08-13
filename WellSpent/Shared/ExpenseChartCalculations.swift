import WellSpentAPI

/// Builds pie/bar chart data for the Expense Plan and Expense Overview
/// tabs — mirrors web's chart-data construction in `ExpensesPanel.tsx`/
/// `ExpenseOverviewPanel.tsx` (both feed `ExpenseChart.tsx`). Kept free of
/// network/view-model state so it's directly testable.
nonisolated enum ExpenseChartCalculations {
    struct Datum: Identifiable, Equatable {
        let id: Int32
        let name: String
        let value: Double
        let colorHex: String
    }

    /// Same 8-color rotation web falls back to when a category has no
    /// assigned color (`CHART_COLORS` in `ExpensesPanel.tsx`/
    /// `ExpenseOverviewPanel.tsx`).
    static let fallbackPalette = ["#6366f1", "#22c55e", "#f59e0b", "#ef4444", "#3b82f6", "#a855f7", "#14b8a6", "#f97316"]

    static func amountValue(units: Int64, nanos: Int32) -> Double {
        Double(units) + Double(nanos) / 1_000_000_000
    }

    /// Resolves the datum a pie selection landed on.
    ///
    /// `chartAngleSelection` reports a position along the *accumulated value*
    /// scale rather than an index — a tap on the third of three equal $100
    /// slices comes back as something in `(200, 300]`, not `2` — so this walks
    /// the running total in the same order `Chart(data)` lays the sectors out.
    /// Returns nil past the end of the data, which is what a tap outside the
    /// ring produces.
    static func datum(atAngleValue value: Double, in data: [Datum]) -> Datum? {
        var cumulative = 0.0
        for datum in data {
            cumulative += datum.value
            if value <= cumulative { return datum }
        }
        return nil
    }

    /// A datum's share of the chart, as a 0–100 percentage. Zero when there's
    /// nothing to divide by, so an empty or all-zero chart can't produce NaN.
    static func percentage(of value: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return value / total * 100
    }

    /// Builds chart data from categories + an amount lookup + an optional
    /// per-category color override (Overview uses this to flag overspent
    /// categories red, matching web's `isOver ? '#ef4444' : ...`). Filters
    /// out non-positive amounts, matching web's `.filter((d) => d.value > 0)`.
    static func data(
        categories: [Wellspent_V1_Category],
        amount: (Wellspent_V1_Category) -> (units: Int64, nanos: Int32),
        colorOverride: (Wellspent_V1_Category) -> String? = { _ in nil }
    ) -> [Datum] {
        categories.enumerated().compactMap { index, category in
            let a = amount(category)
            let value = amountValue(units: a.units, nanos: a.nanos)
            guard value > 0 else { return nil }
            let color = colorOverride(category) ?? (category.color.isEmpty ? fallbackPalette[index % fallbackPalette.count] : category.color)
            return Datum(id: category.id, name: category.name, value: value, colorHex: color)
        }
    }
}
