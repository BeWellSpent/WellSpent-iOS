import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("ExpenseChartCalculations")
struct ExpenseChartCalculationsTests {
    private func category(id: Int32, name: String, color: String = "") -> Wellspent_V1_Category {
        .with {
            $0.id = id
            $0.name = name
            $0.color = color
        }
    }

    @Test("uses the category's own color when set")
    func usesCategoryColor() {
        let categories = [category(id: 1, name: "Groceries", color: "#123456")]
        let data = ExpenseChartCalculations.data(categories: categories, amount: { _ in (100, 0) })
        #expect(data.first?.colorHex == "#123456")
    }

    @Test("falls back to the palette, rotating by index, when a category has no color")
    func fallsBackToPalette() {
        let categories = (0..<10).map { category(id: Int32($0), name: "Cat \($0)") }
        let data = ExpenseChartCalculations.data(categories: categories, amount: { _ in (10, 0) })
        #expect(data[0].colorHex == ExpenseChartCalculations.fallbackPalette[0])
        #expect(data[8].colorHex == ExpenseChartCalculations.fallbackPalette[0]) // wraps after 8 colors
    }

    @Test("filters out non-positive amounts")
    func filtersNonPositiveAmounts() {
        let categories = [
            category(id: 1, name: "Zero"),
            category(id: 2, name: "Negative"),
            category(id: 3, name: "Positive"),
        ]
        let amounts: [Int32: (units: Int64, nanos: Int32)] = [1: (0, 0), 2: (-5, 0), 3: (5, 0)]
        let data = ExpenseChartCalculations.data(categories: categories, amount: { amounts[$0.id] ?? (0, 0) })
        #expect(data.map(\.name) == ["Positive"])
    }

    @Test("colorOverride takes priority over the category's own color")
    func colorOverrideWins() {
        let categories = [category(id: 1, name: "Overspent", color: "#00FF00")]
        let data = ExpenseChartCalculations.data(
            categories: categories,
            amount: { _ in (100, 0) },
            colorOverride: { _ in "#FF0000" }
        )
        #expect(data.first?.colorHex == "#FF0000")
    }

    @Test("amountValue combines units and nanos into a decimal")
    func amountValueCombinesUnitsAndNanos() {
        #expect(ExpenseChartCalculations.amountValue(units: 10, nanos: 500_000_000) == 10.5)
    }
}
