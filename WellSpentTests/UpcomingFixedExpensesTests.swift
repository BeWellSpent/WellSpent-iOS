import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("UpcomingFixedExpenses")
struct UpcomingFixedExpensesTests {
    private func expense(id: String, isActive: Bool = true) -> Wellspent_V1_FixedExpense {
        .with {
            $0.id = id
            $0.name = "Rent"
            $0.isActive = isActive
        }
    }

    private func transaction(fixedExpenseID: String) -> Wellspent_V1_Transaction {
        .with {
            $0.id = "tx-\(fixedExpenseID)"
            $0.fixedExpenseID = fixedExpenseID
        }
    }

    @Test("Active templates with nothing spawned this period are upcoming")
    func returnsTemplatesWithoutTransactions() {
        // These are the bills that would otherwise be invisible until the
        // period they land in.
        let rent = expense(id: "fe-rent")
        let gym = expense(id: "fe-gym")

        let result = UpcomingFixedExpenses.notDue(
            expenses: [rent, gym],
            transactions: [transaction(fixedExpenseID: "fe-rent")]
        )

        #expect(result.map(\.id) == ["fe-gym"])
    }

    @Test("A deactivated template is not upcoming")
    func ignoresDeactivatedTemplates() {
        // A completed payment plan auto-deactivates — nothing more is coming.
        let cancelled = expense(id: "fe-old", isActive: false)

        #expect(UpcomingFixedExpenses.notDue(expenses: [cancelled], transactions: []).isEmpty)
    }

    @Test("Nothing is upcoming on an archived period")
    func suppressedWhenArchived() {
        // ListFixedExpenses is profile-scoped, so without this a closed period
        // would list every template created since as "upcoming" in a month
        // that already ended.
        let rent = expense(id: "fe-rent")

        let result = UpcomingFixedExpenses.notDue(
            expenses: [rent],
            transactions: [],
            isArchivedPeriod: true
        )

        #expect(result.isEmpty)
    }

    @Test("Another template's transaction doesn't mark this one as due")
    func matchesOnIdentityNotPresence() {
        let rent = expense(id: "fe-rent")
        let gym = expense(id: "fe-gym")

        let result = UpcomingFixedExpenses.notDue(
            expenses: [rent, gym],
            transactions: [transaction(fixedExpenseID: "fe-other")]
        )

        #expect(result.map(\.id) == ["fe-rent", "fe-gym"])
    }

    @Test("Nothing is upcoming once every active template has spawned")
    func emptyWhenAllSpawned() {
        let rent = expense(id: "fe-rent")

        let result = UpcomingFixedExpenses.notDue(
            expenses: [rent],
            transactions: [transaction(fixedExpenseID: "fe-rent")]
        )

        #expect(result.isEmpty)
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
