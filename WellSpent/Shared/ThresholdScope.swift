/// `AlertSubscription.threshold_scope` is a plain string on the wire
/// (`notification.proto`), only meaningful for `AlertType.spendingThreshold`.
nonisolated enum ThresholdScope: String, CaseIterable {
    case budget
    case category

    var label: String {
        switch self {
        case .budget: return "Whole Budget"
        case .category: return "Per Category"
        }
    }
}
