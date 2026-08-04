import Testing
@testable import WellSpent

@Suite("USState")
struct USStateTests {
    @Test("contains all 50 states plus DC")
    func containsAllStatesPlusDC() {
        #expect(USState.all.count == 51)
    }

    @Test("every code is a unique two-letter USPS code")
    func codesAreUniqueAndTwoLetters() {
        let codes = USState.all.map(\.code)
        #expect(Set(codes).count == codes.count)
        #expect(codes.allSatisfy { $0.count == 2 })
    }

    @Test("name(for:) resolves a known code")
    func nameForKnownCode() {
        #expect(USState.name(for: "CA") == "California")
    }

    @Test("name(for:) returns nil for an unknown code")
    func nameForUnknownCode() {
        #expect(USState.name(for: "ZZ") == nil)
    }
}
