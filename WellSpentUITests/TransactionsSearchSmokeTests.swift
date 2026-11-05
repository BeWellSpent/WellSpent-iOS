import XCTest

/// Verifies the Overview tab's Transactions sub-tab free-text search field
/// actually renders once revealed. This field is a plain `TextField` in
/// `BudgetDetailView.transactionsSearchField`, not SwiftUI's native
/// `.searchable` — that was tried first (both at the outer content level and
/// on the tab's own inner `NavigationStack`) and confirmed dead in both
/// positions via this exact test plus an accessibility-hierarchy dump: no
/// search bar element ever installed at all on this screen's doubly-nested
/// NavigationStack architecture. It now starts hidden behind the header's
/// search icon (issue #92 follow-up) instead of always shown, so this test
/// taps that icon before asserting the field exists. Needs the
/// seeded account (`UITEST_EMAIL`) — a fresh sign-up lands on the
/// email-verification gate, never a budget.
///
/// Updated for the Overview/Plan navigation rework
/// (docs/features/overview-plan-navigation-rework.md): Transactions is no
/// longer its own bottom tab — it's reached via Overview's sub-tab picker.
final class TransactionsSearchSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSearchFieldExistsOnTransactionsTab() throws {
        let app = XCUIApplication()
        try signInToEmptyAccount(app)

        createBudget(app, name: "UITest Search Budget \(Int(Date().timeIntervalSince1970))")

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        homeTab.tap()

        // Home's sub-tab picker defaults to Overview (totals + chart, one
        // combined panel — see docs/features/overview-plan-navigation-rework.md's
        // second layout correction), so Transactions needs an explicit tap.
        let transactionsSubTab = app.buttons["Transactions"]
        XCTAssertTrue(transactionsSubTab.waitForExistence(timeout: 10))
        transactionsSubTab.tap()

        let searchToggleButton = app.buttons["transactionsSearchToggleButton"]
        XCTAssertTrue(searchToggleButton.waitForExistence(timeout: 10))
        searchToggleButton.tap()

        let searchField = app.textFields["transactionsSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field should be visible after tapping the header's search icon")

        // Cleanup: delete the budget so this test leaves no orphan data behind.
        deleteCurrentBudget(app)
    }
}
