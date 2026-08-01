import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TransactionDayGrouping")
struct TransactionDayGroupingTests {
    private func transaction(id: String, date: Date) -> Wellspent_V1_Transaction {
        .with {
            $0.id = id
            $0.date = Google_Protobuf_Timestamp(date: date)
        }
    }

    @Test("transactions on the same calendar day bucket together regardless of time")
    func sameDayDifferentTimeBucketsTogether() {
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let evening = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!

        let groups = TransactionDayGrouping.group([
            transaction(id: "1", date: morning),
            transaction(id: "2", date: evening)
        ])

        #expect(groups.count == 1)
        #expect(Set(groups[0].transactions.map(\.id)) == ["1", "2"])
    }

    @Test("day groups are ordered newest-first")
    func groupsOrderedNewestFirst() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!

        let groups = TransactionDayGrouping.group([
            transaction(id: "old", date: twoDaysAgo),
            transaction(id: "new", date: today),
            transaction(id: "mid", date: yesterday)
        ])

        #expect(groups.map(\.id) == groups.map(\.id).sorted(by: >))
        #expect(groups.first?.transactions.first?.id == "new")
    }

    @Test("empty input produces no groups")
    func emptyInputProducesNoGroups() {
        #expect(TransactionDayGrouping.group([]).isEmpty)
    }

    @Test("headerText produces a non-empty localized string")
    func headerTextIsNonEmpty() {
        let text = TransactionDayGrouping.headerText(for: Date(), localeIdentifier: "en")
        #expect(!text.isEmpty)
    }
}
