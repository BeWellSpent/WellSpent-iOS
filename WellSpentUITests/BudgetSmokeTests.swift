import XCTest

/// End-to-end smoke flow for Phase 2A: create a budget, add a person, add an
/// income source, confirm both appear, then delete the budget as cleanup so
/// repeated runs don't leave orphan data on the real backend. Requires a
/// seeded account (`UITEST_EMAIL`/`UITEST_PASSWORD`), same as `LoginSmokeTests`.
/// The seeded account must be able to get past the email-verification gate —
/// either genuinely verified, or marked exempt with
/// `UPDATE users SET account_type = 'test' WHERE email = '<UITEST_EMAIL>';`
/// (see WellSpent-backend migration 000045). Without that, login succeeds but
/// lands on the gate instead of the budget list.
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

        // The setup wizard opens on step 2 (People) once the budget is
        // created; skip through People/Income/Payment Methods here and add
        // the person/income source afterward via the regular panels, same
        // as before the wizard existed.
        for _ in 0..<3 {
            let skipButton = app.buttons["setupSkipButton"]
            XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
            skipButton.tap()
        }

        // Finishing setup lands straight on the budget — it is the home
        // screen now (issue #60), there is no list in between. The manage
        // panels moved behind the ☰.
        XCTAssertTrue(waitForBudgetHome(app), "expected the budget home screen after setup")
        XCTAssertTrue(openManagePanels(app), "expected the ☰ menu to open the manage panels")

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
        // Edit/Delete live on the manage screen's own toolbar now that it is a
        // pushed destination rather than a tab.
        let detailMenu = app.buttons["budgetDetailMenu"]
        XCTAssertTrue(detailMenu.waitForExistence(timeout: 5))
        detailMenu.tap()
        app.buttons["Delete Budget"].tap()
        app.buttons["Delete"].tap()

        // Deleting the only budget drops the home screen back to its empty
        // state, which is where addBudgetButton lives now.
        XCTAssertTrue(app.buttons["addBudgetButton"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts[budgetName].exists)
    }
}
