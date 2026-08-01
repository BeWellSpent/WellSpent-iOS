import WellSpentAPI

/// Display text for an `IncomeType`.
nonisolated enum IncomeTypeLabel {
    static func text(for type: Wellspent_V1_IncomeType) -> String {
        switch type {
        case .unspecified: return "Unspecified"
        case .salary: return "Salary"
        case .hourly: return "Hourly"
        case .freelance: return "Freelance"
        case .contractor: return "Contractor"
        case .investment: return "Investment"
        case .interest: return "Interest"
        case .oneTime: return "One-time"
        case .gift: return "Gift"
        case .other: return "Other"
        case .UNRECOGNIZED: return "Unknown"
        }
    }

    /// All selectable types, in display order, for pickers.
    static let selectable: [Wellspent_V1_IncomeType] = [
        .salary, .hourly, .freelance, .contractor, .investment, .interest, .oneTime, .gift, .other,
    ]
}
