import Testing
@testable import WellSpent

@Suite("SavingsFrequencyLabel")
struct SavingsFrequencyLabelTests {
    @Test("1 day is Monthly")
    func oneDayIsMonthly() {
        #expect(SavingsFrequencyLabel.text(forDayCount: 1) == "Monthly")
    }

    @Test("2 days is Bi-weekly")
    func twoDaysIsBiWeekly() {
        #expect(SavingsFrequencyLabel.text(forDayCount: 2) == "Bi-weekly")
    }

    @Test("4 days is Weekly")
    func fourDaysIsWeekly() {
        #expect(SavingsFrequencyLabel.text(forDayCount: 4) == "Weekly")
    }

    @Test("any other count has no label", arguments: [0, 3, 5, 10])
    func otherCountsAreBlank(count: Int) {
        #expect(SavingsFrequencyLabel.text(forDayCount: count).isEmpty)
    }
}
