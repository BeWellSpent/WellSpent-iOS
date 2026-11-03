import Testing
@testable import WellSpent

@Suite("IncomeJobReconciliation")
struct IncomeJobReconciliationTests {
    @Test("same count produces one update per row, in order")
    func sameCountUpdatesEveryRow() {
        let actions = IncomeJobReconciliation.diff(existingCount: 3, newDateCount: 3)
        #expect(actions == [
            .update(existingIndex: 0, dateIndex: 0),
            .update(existingIndex: 1, dateIndex: 1),
            .update(existingIndex: 2, dateIndex: 2),
        ])
    }

    @Test("more new dates than existing rows updates the shared ones and adds the rest")
    func moreDatesAddsExtra() {
        let actions = IncomeJobReconciliation.diff(existingCount: 2, newDateCount: 4)
        #expect(actions == [
            .update(existingIndex: 0, dateIndex: 0),
            .update(existingIndex: 1, dateIndex: 1),
            .add(dateIndex: 2),
            .add(dateIndex: 3),
        ])
    }

    @Test("fewer new dates than existing rows updates the shared ones and deletes the rest")
    func fewerDatesDeletesExtra() {
        let actions = IncomeJobReconciliation.diff(existingCount: 4, newDateCount: 1)
        #expect(actions == [
            .update(existingIndex: 0, dateIndex: 0),
            .delete(existingIndex: 1),
            .delete(existingIndex: 2),
            .delete(existingIndex: 3),
        ])
    }

    @Test("no existing rows adds every date, used by the add-mode multi-payday path")
    func noExistingRowsAddsEverything() {
        let actions = IncomeJobReconciliation.diff(existingCount: 0, newDateCount: 2)
        #expect(actions == [.add(dateIndex: 0), .add(dateIndex: 1)])
    }

    @Test("no new dates deletes every existing row")
    func noNewDatesDeletesEverything() {
        let actions = IncomeJobReconciliation.diff(existingCount: 2, newDateCount: 0)
        #expect(actions == [.delete(existingIndex: 0), .delete(existingIndex: 1)])
    }

    @Test("zero and zero is a no-op")
    func zeroAndZeroIsNoOp() {
        #expect(IncomeJobReconciliation.diff(existingCount: 0, newDateCount: 0).isEmpty)
    }
}
