import Foundation

/// Pure diff between a logical income job's existing `IncomeSource` rows and
/// the new set of pay dates a save produced. Operates on counts/indices only
/// — the caller maps `existingIndex`/`dateIndex` back to real ids/dates,
/// both of which must already be in the same stable order (sorted by anchor
/// date ascending, see `IncomeJobGrouping.sortedRows`) before calling this.
/// Same count maps row-for-row; a shrink drops the trailing existing rows
/// (losing their forked-row history is correct — the user is saying "this
/// payday no longer exists"); a growth adds new rows for the extra dates.
nonisolated enum IncomeJobReconciliation {
    enum Action: Equatable {
        case update(existingIndex: Int, dateIndex: Int)
        case add(dateIndex: Int)
        case delete(existingIndex: Int)
    }

    static func diff(existingCount: Int, newDateCount: Int) -> [Action] {
        let shared = min(existingCount, newDateCount)
        var actions = (0..<shared).map { Action.update(existingIndex: $0, dateIndex: $0) }
        if newDateCount > existingCount {
            actions += (existingCount..<newDateCount).map { Action.add(dateIndex: $0) }
        } else if existingCount > newDateCount {
            actions += (newDateCount..<existingCount).map { Action.delete(existingIndex: $0) }
        }
        return actions
    }
}
