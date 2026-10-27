import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("UpcomingFixedExpenses")
struct UpcomingFixedExpensesTests {
    private func expense(id: String) -> Wellspent_V1_FixedExpense {
        .with {
            $0.id = id
            $0.name = "Rent"
            $0.isActive = true
        }
    }

    @Test("Next-due text is empty when the backend supplied no date")
    func nextDueTextEmptyWithoutDate() {
        let text = UpcomingFixedExpenses.nextDueText(for: expense(id: "fe-rent"), localeIdentifier: "en")
        #expect(text.isEmpty)
    }

    @Test("Next-due text reads the calendar day the backend meant")
    func nextDueTextUsesDateOnly() {
        // next_due_date is a DATE-only value encoded as midnight UTC. Reading
        // the raw timestamp in a timezone behind UTC lands a day early — the
        // v1.15.1 bug — so this must go through `dateOnly`.
        var due = DateComponents()
        due.year = 2026
        due.month = 9
        due.day = 1
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnightUTC = utc.date(from: due)!

        let fixedExpense = Wellspent_V1_FixedExpense.with {
            $0.id = "fe-rent"
            $0.nextDueDate = Google_Protobuf_Timestamp(date: midnightUTC)
        }

        let text = UpcomingFixedExpenses.nextDueText(for: fixedExpense, localeIdentifier: "en")

        #expect(text.contains("1"))
        #expect(text.contains("Sep"))
    }
}
