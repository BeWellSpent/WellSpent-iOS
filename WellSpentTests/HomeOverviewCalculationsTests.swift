import Foundation
import Testing
@testable import WellSpent

@Suite("HomeOverviewCalculations")
struct HomeOverviewCalculationsTests {
    private typealias Calc = HomeOverviewCalculations

    @Test("A bar's fraction is clamped to 0...1 and is 0 with nothing planned")
    func fraction() {
        #expect(Calc.fraction((50, 0), of: (200, 0)) == 0.25)
        #expect(Calc.fraction((300, 0), of: (200, 0)) == 1)
        #expect(Calc.fraction((-20, 0), of: (200, 0)) == 0)
        #expect(Calc.fraction((50, 0), of: (0, 0)) == 0)
    }

    @Test("Remaining is planned minus spent, negative when over")
    func remaining() {
        let left = Calc.remaining(spent: (2188, 0), planned: (2900, 0))
        #expect(left.units == 712 && left.nanos == 0)
        let over = Calc.remaining(spent: (2386, 0), planned: (2300, 0))
        #expect(over.units == -86)
        #expect(Calc.isOver(spent: (2386, 0), planned: (2300, 0)))
        #expect(!Calc.isOver(spent: (2300, 0), planned: (2300, 0)))
    }

    @Test("Savings: met at plan, short below it, neutral with no plan")
    func savedStatus() {
        #expect(Calc.savedStatus(saved: (400, 0), planned: (400, 0)) == .met)
        #expect(Calc.savedStatus(saved: (0, 0), planned: (300, 0)) == .short)
        #expect(Calc.savedStatus(saved: (50, 0), planned: (0, 0)) == .neutral)
    }

    @Test("Income: met once all planned income arrived, otherwise neutral, never a warning")
    func incomeStatus() {
        #expect(Calc.incomeStatus(received: (3400, 0), planned: (3400, 0)) == .met)
        #expect(Calc.incomeStatus(received: (1500, 0), planned: (3000, 0)) == .neutral)
        #expect(Calc.incomeStatus(received: (0, 0), planned: (0, 0)) == .neutral)
    }

    @Test("Collapsed shows the top 3 in server order; expanded shows all")
    func visibleRows() {
        let rows = ["Rent", "Groceries", "Car loan", "Dining", "Shopping"]
        #expect(Calc.visibleRows(rows, expanded: false) == ["Rent", "Groceries", "Car loan"])
        #expect(Calc.visibleRows(rows, expanded: true) == rows)
        #expect(Calc.visibleRows(["Rent"], expanded: false) == ["Rent"])
    }

    @Test("Segments: top 5 named, the rest folded into Other, refunds take no space, shares sum to 1")
    func segments() {
        let items: [Calc.ChartItem] = [
            .init(id: "1", name: "Rent", colorHex: "#111111", amount: (1850, 0)),
            .init(id: "2", name: "Groceries", colorHex: "#222222", amount: (742, 0)),
            .init(id: "3", name: "Car loan", colorHex: "#333333", amount: (420, 0)),
            .init(id: "4", name: "Dining", colorHex: "#444444", amount: (382, 0)),
            .init(id: "5", name: "Shopping", colorHex: "#555555", amount: (296, 0)),
            .init(id: "6", name: "Utilities", colorHex: "#666666", amount: (228, 0)),
            .init(id: "7", name: "Gifts", colorHex: "#777777", amount: (50, 0)),
            .init(id: "8", name: "Refunds", colorHex: "#888888", amount: (-30, 0)),
        ]
        let segments = Calc.segments(items, otherName: "Other")
        #expect(segments.map(\.name) == ["Rent", "Groceries", "Car loan", "Dining", "Shopping", "Other"])
        #expect(segments.last?.id == Calc.otherSegmentID)
        let total = segments.reduce(0) { $0 + $1.fraction }
        #expect(abs(total - 1) < 0.000_001)
    }

    @Test("Segments: nothing spent means no chart")
    func noSegments() {
        #expect(Calc.segments([.init(id: "1", name: "Rent", colorHex: "#111111", amount: (0, 0))], otherName: "Other").isEmpty)
    }
}
