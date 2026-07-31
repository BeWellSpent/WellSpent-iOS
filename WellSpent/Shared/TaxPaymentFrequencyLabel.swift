import WellSpentAPI

/// Display text for a `TaxPaymentFrequency`.
nonisolated enum TaxPaymentFrequencyLabel {
    static func text(for frequency: Wellspent_V1_TaxPaymentFrequency) -> String {
        switch frequency {
        case .unspecified: return "Not set"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .fourMonthly: return "Every 4 months"
        case .semiAnnual: return "Semi-annual"
        case .annual: return "Annual"
        case .UNRECOGNIZED: return "Unknown"
        }
    }

    /// All selectable frequencies, in display order, for pickers.
    static let selectable: [Wellspent_V1_TaxPaymentFrequency] = [
        .monthly, .quarterly, .fourMonthly, .semiAnnual, .annual,
    ]
}
