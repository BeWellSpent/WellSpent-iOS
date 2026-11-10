/// The chart style a person picks for Home and Plan, saved per person per
/// budget (`ChartPreference`) and drawn by `HomeSpendingChart`.
enum ExpenseChartType: String, CaseIterable {
    case pie
    case bar
}
