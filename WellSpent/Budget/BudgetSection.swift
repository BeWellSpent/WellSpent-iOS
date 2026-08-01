/// Top-level destination within a budget: shown as a bottom tab bar on
/// iPhone and a sidebar (`NavigationSplitView`) on iPad. Collapses web's two
/// independent nav layers (top tabs for Plan/Transactions/... + a separate
/// sidebar/drawer for Income/Savings/Payment Methods/Categories/People) into
/// one adaptive structure — iOS has no good native equivalent of a second
/// persistent nav rail alongside a tab bar.
enum BudgetSection: CaseIterable, Hashable {
    case plan
    case transactions
    case manage

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .transactions: return "Transactions"
        case .manage: return "Manage"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: return "chart.pie"
        case .transactions: return "list.bullet"
        case .manage: return "slider.horizontal.3"
        }
    }
}
