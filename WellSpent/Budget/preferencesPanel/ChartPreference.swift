import Foundation
import WellSpentAPI

/// Maps a person's stored chart preference onto the chart the view should
/// open with. Pure so the fallback is testable without a view or a network
/// call — the whole point is that an unset preference must not render as an
/// empty or arbitrary chart.
nonisolated enum ChartPreference {
    /// Both tabs open as a pie unless the person chose otherwise. Overview
    /// used to default to bar; with the chart configurable, one consistent
    /// starting point beats two.
    static let fallback: ExpenseChartView.ChartType = .pie

    static func chartType(for stored: Wellspent_V1_ChartType) -> ExpenseChartView.ChartType {
        switch stored {
        case .pie: return .pie
        case .bar: return .bar
        default: return fallback
        }
    }

    static func stored(for chartType: ExpenseChartView.ChartType) -> Wellspent_V1_ChartType {
        switch chartType {
        case .pie: return .pie
        case .bar: return .bar
        }
    }

    /// The caller's own row on a budget. Preferences are per person, so the
    /// row is matched by user ID — the same resolution `BudgetRoleResolver`
    /// already does for roles.
    static func myPerson(
        currentUserID: String?,
        people: [Wellspent_V1_BudgetPerson]
    ) -> Wellspent_V1_BudgetPerson? {
        guard let currentUserID, !currentUserID.isEmpty else { return nil }
        return people.first { !$0.userID.isEmpty && $0.userID == currentUserID }
    }
}
