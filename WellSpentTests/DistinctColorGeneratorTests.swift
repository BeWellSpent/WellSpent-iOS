import Testing
@testable import WellSpent

@Suite("DistinctColorGenerator")
struct DistinctColorGeneratorTests {
    @Test("generate returns the requested count of valid hex strings")
    func generateReturnsRequestedCount() {
        let colors = DistinctColorGenerator.generate(count: 5, startHue: 0)
        #expect(colors.count == 5)
        for color in colors {
            #expect(color.hasPrefix("#"))
            #expect(color.count == 7)
        }
    }

    @Test("generate returns an empty array for zero or negative count")
    func generateReturnsEmptyForNonPositiveCount() {
        #expect(DistinctColorGenerator.generate(count: 0, startHue: 0).isEmpty)
        #expect(DistinctColorGenerator.generate(count: -3, startHue: 0).isEmpty)
    }

    @Test("generate is deterministic for a fixed start hue")
    func generateIsDeterministicForFixedStartHue() {
        let first = DistinctColorGenerator.generate(count: 4, startHue: 90)
        let second = DistinctColorGenerator.generate(count: 4, startHue: 90)
        #expect(first == second)
    }

    @Test("generate produces distinct colors across the set")
    func generateProducesDistinctColors() {
        let colors = DistinctColorGenerator.generate(count: 6, startHue: 0)
        #expect(Set(colors).count == colors.count)
    }
}
