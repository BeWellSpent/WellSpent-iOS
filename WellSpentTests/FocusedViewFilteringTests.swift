import Testing
@testable import WellSpent

@Suite("FocusedViewFiltering")
struct FocusedViewFilteringTests {
    @Test("includes a row attributed to the caller")
    func includesMine() {
        #expect(FocusedViewFiltering.isMineOrUnattributed(1, myPersonID: 1))
    }

    @Test("includes an unattributed row regardless of who the caller is")
    func includesUnattributed() {
        #expect(FocusedViewFiltering.isMineOrUnattributed(0, myPersonID: 1))
    }

    @Test("excludes a row attributed to someone else")
    func excludesSomeoneElse() {
        #expect(!FocusedViewFiltering.isMineOrUnattributed(2, myPersonID: 1))
    }

    @Test("excludes everyone when the caller has no resolved person id")
    func excludesWhenCallerUnresolved() {
        #expect(!FocusedViewFiltering.isMineOrUnattributed(2, myPersonID: nil))
    }
}
