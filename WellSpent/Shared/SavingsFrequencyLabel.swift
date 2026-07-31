/// Display label for a savings source's schedule, derived purely from how
/// many `payment_days` are set — mirrors web's `inferFrequencyLabel`. There
/// is no frequency picker anywhere in the create/edit forms; the count of
/// selected calendar days *is* the frequency.
nonisolated enum SavingsFrequencyLabel {
    static func text(forDayCount count: Int) -> String {
        switch count {
        case 1: return "Monthly"
        case 2: return "Bi-weekly"
        case 4: return "Weekly"
        default: return ""
        }
    }
}
