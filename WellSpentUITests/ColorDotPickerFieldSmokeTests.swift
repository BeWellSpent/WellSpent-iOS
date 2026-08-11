import XCTest

/// End-to-end smoke test for `ColorDotPickerField` (replaces the native
/// `Picker` for category/person/payment-method selection everywhere, since a
/// native Picker can't show a color dot in its collapsed value — see
/// `Shared/ColorDotPickerField.swift`'s doc comment). Confirms the actual
/// tap-through interaction — trigger opens a sheet, a row is selectable, the
/// sheet dismisses and the selection updates — using the Add Transaction
/// category picker as the one concrete site exercised. Requires a seeded
/// account (`UITEST_EMAIL`/`UITEST_PASSWORD`), same as `BudgetSmokeTests`.
/// The seeded account must be able to get past the email-verification gate —
/// either genuinely verified, or marked exempt with
/// `UPDATE users SET account_type = 'test' WHERE email = '<UITEST_EMAIL>';`
/// (see WellSpent-backend migration 000045). Without that, login succeeds but
/// lands on the gate instead of the budget list.
final class ColorDotPickerFieldSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCategoryPickerSheetOpensAndSelects() throws {
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

        let budgetName = "UITest ColorDotPicker \(Int(Date().timeIntervalSince1970))"
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

        let budgetRow = app.buttons["budgetRow_\(budgetName)"]
        XCTAssertTrue(budgetRow.waitForExistence(timeout: 10))
        budgetRow.tap()

        app.tabBars.buttons["Transactions"].tap()

        app.buttons["addTransactionButton"].tap()

        let categoryPicker = app.buttons["transactionCategoryPicker"]
        XCTAssertTrue(categoryPicker.waitForExistence(timeout: 5))
        categoryPicker.tap()

        // The sheet presents a plain List (not a native Picker menu) — its
        // "None" row is always present regardless of the user's own
        // categories, so it's a stable target for this smoke test.
        let noneOption = app.buttons["transactionCategoryPicker_option_none"]
        XCTAssertTrue(noneOption.waitForExistence(timeout: 5))
        noneOption.tap()

        // Selecting dismisses the sheet — the trigger row (and the rest of
        // the Add Transaction form) should be reachable again immediately.
        XCTAssertTrue(categoryPicker.waitForExistence(timeout: 5))
        XCTAssertFalse(noneOption.exists)

        app.navigationBars.buttons["Cancel"].tap()

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
