import XCTest

/// End-to-end smoke flow for Phase 2A: create a budget, add a person, add an
/// income source, confirm both appear, then delete the budget as cleanup so
/// repeated runs don't leave orphan data on the real backend. Requires a
/// seeded account (`UITEST_EMAIL`/`UITEST_PASSWORD`), same as `LoginSmokeTests`.
final class BudgetSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateBudgetAddPersonAndIncome() throws {
        guard let email = ProcessInfo.processInfo.environment["UITEST_EMAIL"],
              let password = ProcessInfo.processInfo.environment["UITEST_PASSWORD"] else {
            throw XCTSkip("Set UITEST_EMAIL / UITEST_PASSWORD to run this test against a seeded account.")
        }

        let app = XCUIApplication()
        app.launchArguments = ["-uiTestResetSession"]
        app.launch()

        let emailField = app.textFields["emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["loginButton"].tap()
        dismissSavePasswordPromptIfPresent(app)

        XCTAssertTrue(app.buttons["addBudgetButton"].waitForExistence(timeout: 10))

        // Create a budget with a unique name so repeated runs don't collide.
        let budgetName = "UITest Budget \(Int(Date().timeIntervalSince1970))"
        app.buttons["addBudgetButton"].tap()

        let nameField = app.textFields["budgetNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(budgetName)
        app.buttons["createBudgetButton"].tap()

        let budgetRow = app.buttons["budgetRow_\(budgetName)"]
        XCTAssertTrue(budgetRow.waitForExistence(timeout: 10))
        budgetRow.tap()

        // People
        let peopleLink = app.buttons["peopleNavLink"]
        XCTAssertTrue(peopleLink.waitForExistence(timeout: 5))
        peopleLink.tap()

        let personNameField = app.textFields["addPersonNameField"]
        XCTAssertTrue(personNameField.waitForExistence(timeout: 5))
        personNameField.tap()
        personNameField.typeText("Test Person")
        app.buttons["addPersonButton"].tap()

        XCTAssertTrue(app.staticTexts["Test Person"].waitForExistence(timeout: 10))

        app.navigationBars.buttons.firstMatch.tap()

        // Income
        let incomeLink = app.buttons["incomeNavLink"]
        XCTAssertTrue(incomeLink.waitForExistence(timeout: 5))
        incomeLink.tap()

        app.buttons["addIncomeSourceButton"].tap()

        let incomeNameField = app.textFields["incomeNameField"]
        XCTAssertTrue(incomeNameField.waitForExistence(timeout: 5))
        incomeNameField.tap()
        incomeNameField.typeText("Test Salary")

        let incomeAmountField = app.textFields["incomeAmountField"]
        incomeAmountField.tap()
        incomeAmountField.typeText("1000")

        app.buttons["saveIncomeButton"].tap()

        XCTAssertTrue(app.buttons["incomeRow_Test Salary"].waitForExistence(timeout: 10))

        app.navigationBars.buttons.firstMatch.tap()

        // Cleanup: delete the budget so the test leaves no orphan data behind.
        let detailMenu = app.buttons["budgetDetailMenu"]
        XCTAssertTrue(detailMenu.waitForExistence(timeout: 5))
        detailMenu.tap()
        app.buttons["Delete Budget"].tap()
        app.buttons["Delete"].tap()

        XCTAssertTrue(app.buttons["addBudgetButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["budgetRow_\(budgetName)"].exists)
    }
}
