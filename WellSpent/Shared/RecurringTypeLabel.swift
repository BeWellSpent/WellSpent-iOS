import WellSpentAPI

/// Display text for a `RecurringType` (used as income's payment frequency).
nonisolated enum RecurringTypeLabel {
    static func text(for type: Wellspent_V1_RecurringType) -> String {
        switch type {
        case .unspecified: return "Unspecified"
        case .oneOff: return "One-off"
        case .weekly: return "Weekly"
        case .biWeekly: return "Bi-weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .UNRECOGNIZED: return "Unknown"
        }
    }

    /// All selectable frequencies, in display order, for pickers.
    static let selectable: [Wellspent_V1_RecurringType] = [.oneOff, .weekly, .biWeekly, .monthly, .yearly]
}
