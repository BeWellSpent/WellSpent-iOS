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
        let app = XCUIApplication()
        try signInToEmptyAccount(app)

        // Unique name so repeated runs don't collide.
        let budgetName = "UITest Budget \(Int(Date().timeIntervalSince1970))"
        createBudget(app, name: budgetName)

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

        app.buttons["BackButton"].tap()

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

        app.buttons["BackButton"].tap()

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
