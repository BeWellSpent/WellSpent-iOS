import WellSpentAPI

/// Display text for a `FilingStatus`.
nonisolated enum FilingStatusLabel {
    static func text(for status: Wellspent_V1_FilingStatus) -> String {
        switch status {
        case .unspecified: return "Not set"
        case .single: return "Single"
        case .marriedFilingJointly: return "Married Filing Jointly"
        case .marriedFilingSeparately: return "Married Filing Separately"
        case .headOfHousehold: return "Head of Household"
        case .qualifyingSurvivingSpouse: return "Qualifying Surviving Spouse"
        case .UNRECOGNIZED: return "Unknown"
        }
    }

    /// All selectable statuses, in display order, for pickers.
    static let selectable: [Wellspent_V1_FilingStatus] = [
        .single, .marriedFilingJointly, .marriedFilingSeparately, .headOfHousehold, .qualifyingSurvivingSpouse,
    ]
}
