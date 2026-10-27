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
/// taps that icon before asserting the field exists. No seeded account
/// needed — same fresh-email pattern as `RegisterSmokeTests`.
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
        app.launchArguments = ["-uiTestResetSession"]
        app.launch()

        let registerLink = app.buttons["goToRegisterLink"]
        XCTAssertTrue(registerLink.waitForExistence(timeout: 5))
        registerLink.tap()

        let firstNameField = app.textFields["firstNameField"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 5))
        firstNameField.tap()
        firstNameField.typeText("Ada")

        let lastNameField = app.textFields["lastNameField"]
        lastNameField.tap()
        lastNameField.typeText("Lovelace")

        let emailField = app.textFields["registerEmailField"]
        emailField.tap()
        emailField.typeText("ios-uitest-search-\(Int(Date().timeIntervalSince1970))@example.com")

        let passwordField = app.secureTextFields["registerPasswordField"]
        passwordField.tap()
        passwordField.typeText("Valid1Password!")

        app.buttons["registerButton"].tap()
        dismissSavePasswordPromptIfPresent(app)

        XCTAssertTrue(app.buttons["addBudgetButton"].waitForExistence(timeout: 10))

        let budgetName = "UITest Search Budget \(Int(Date().timeIntervalSince1970))"
        app.buttons["addBudgetButton"].tap()

        let nameField = app.textFields["budgetNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(budgetName)
        app.buttons["createBudgetButton"].tap()

        for _ in 0..<3 {
            let skipButton = app.buttons["setupSkipButton"]
            XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
            skipButton.tap()
        }

        XCTAssertTrue(waitForBudgetHome(app), "expected the budget home screen after setup")

        let overviewTab = app.tabBars.buttons["Overview"]
        XCTAssertTrue(overviewTab.waitForExistence(timeout: 10))
        overviewTab.tap()

        // Overview's sub-tab picker defaults to Transactions already (the
        // chart/totals content is always-rendered chrome around it now, not
        // a competing picker segment — see the layout correction in
        // docs/features/overview-plan-navigation-rework.md) — tapping the
        // segment again is harmless and keeps this test explicit either way.
        let transactionsSubTab = app.buttons["Transactions"]
        XCTAssertTrue(transactionsSubTab.waitForExistence(timeout: 10))
        transactionsSubTab.tap()

        let searchToggleButton = app.buttons["transactionsSearchToggleButton"]
        XCTAssertTrue(searchToggleButton.waitForExistence(timeout: 10))
        searchToggleButton.tap()

        let searchField = app.textFields["transactionsSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field should be visible after tapping the header's search icon")

        // Cleanup: delete the budget so this test leaves no orphan data behind.
        // There is no Manage tab any more — it lives behind the ☰.
        XCTAssertTrue(openManagePanels(app), "expected the ☰ menu to open the manage panels")
        let detailMenu = app.buttons["budgetDetailMenu"]
        XCTAssertTrue(detailMenu.waitForExistence(timeout: 5))
        detailMenu.tap()
        app.buttons["Delete Budget"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["addBudgetButton"].waitForExistence(timeout: 15))
    }
}
