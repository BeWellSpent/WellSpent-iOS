import XCTest

/// Verifies the Transactions tab's free-text search field actually renders.
/// This field is a plain `TextField` in `BudgetDetailView.transactionsContent`,
/// not SwiftUI's native `.searchable` — that was tried first (both at the
/// outer content level and on the tab's own inner `NavigationStack`) and
/// confirmed dead in both positions via this exact test plus an
/// accessibility-hierarchy dump: no search bar element ever installed at
/// all on this screen's doubly-nested NavigationStack architecture. No
/// seeded account needed — same fresh-email pattern as `RegisterSmokeTests`.
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

        let transactionsTab = app.tabBars.buttons["Transactions"]
        XCTAssertTrue(transactionsTab.waitForExistence(timeout: 10))
        transactionsTab.tap()

        let searchField = app.textFields["transactionsSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field should be visible on the Transactions tab without needing a reveal gesture")

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
