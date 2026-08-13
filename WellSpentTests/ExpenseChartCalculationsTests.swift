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

    // MARK: - Selection (issue #39)

    private var slices: [ExpenseChartCalculations.Datum] {
        [
            .init(id: 1, name: "Rent", value: 1_000, colorHex: "#111111"),
            .init(id: 2, name: "Groceries", value: 400, colorHex: "#222222"),
            .init(id: 3, name: "Dining", value: 100, colorHex: "#333333"),
        ]
    }

    @Test("an angle selection resolves to the slice occupying that arc")
    func datumAtAngleValue() {
        // chartAngleSelection reports a position along the accumulated value
        // scale, so the second slice occupies (1000, 1400].
        #expect(ExpenseChartCalculations.datum(atAngleValue: 1_200, in: slices)?.name == "Groceries")
    }

    @Test("a selection exactly on a boundary belongs to the slice that ends there")
    func datumAtBoundaryValue() {
        // 1000 is the last instant of Rent's arc, not the first of Groceries' —
        // otherwise every boundary tap would jump forward one slice.
        #expect(ExpenseChartCalculations.datum(atAngleValue: 1_000, in: slices)?.name == "Rent")
    }

    @Test("the first and last slices are both reachable")
    func datumAtEdges() {
        #expect(ExpenseChartCalculations.datum(atAngleValue: 1, in: slices)?.name == "Rent")
        #expect(ExpenseChartCalculations.datum(atAngleValue: 1_500, in: slices)?.name == "Dining")
    }

    @Test("a selection past the end of the data resolves to nothing")
    func datumBeyondTotal() {
        // A tap outside the ring lands here; it must not clamp to the last
        // slice and light up a category the user never touched.
        #expect(ExpenseChartCalculations.datum(atAngleValue: 1_501, in: slices) == nil)
        #expect(ExpenseChartCalculations.datum(atAngleValue: 10, in: []) == nil)
    }

    @Test("percentage is a share of the total")
    func percentageOfTotal() {
        #expect(ExpenseChartCalculations.percentage(of: 250, total: 1_000) == 25)
    }

    @Test("percentage is zero when there is nothing to divide by")
    func percentageWithoutTotal() {
        // Guards the empty/all-zero chart against rendering "nan%".
        #expect(ExpenseChartCalculations.percentage(of: 0, total: 0) == 0)
    }
}
