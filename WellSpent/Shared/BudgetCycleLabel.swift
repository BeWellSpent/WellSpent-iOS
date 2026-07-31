import WellSpentAPI

/// Display text for a `BudgetCycle`.
nonisolated enum BudgetCycleLabel {
    static func text(for cycle: Wellspent_V1_BudgetCycle) -> String {
        switch cycle {
        case .unspecified:
            return "Unspecified"
        case .weekly:
            return "Weekly"
        case .biWeekly:
            return "Bi-weekly"
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        case .UNRECOGNIZED:
            return "Unknown"
        }
    }

    /// All selectable cycles, in display order, for pickers.
    static let selectable: [Wellspent_V1_BudgetCycle] = [.weekly, .biWeekly, .monthly, .yearly]
}
