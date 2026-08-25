import XCTest

/// Requires a seeded test account — set `UITEST_EMAIL`/`UITEST_PASSWORD` in
/// the environment before running (skips itself otherwise rather than
/// failing, so a plain `xcodebuild test` run without credentials doesn't
/// report a false failure).
/// The seeded account must be able to get past the email-verification gate —
/// either genuinely verified, or marked exempt with
/// `UPDATE users SET account_type = 'test' WHERE email = '<UITEST_EMAIL>';`
/// (see WellSpent-backend migration 000045). Without that, login succeeds but
/// lands on the gate instead of the budget list.
final class LoginSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoginWithValidCredentialsReachesAuthenticatedScreen() throws {
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

        // Log Out lives in the ☰ menu since issue #60, so a successful login
        // is proven by the budget home screen rather than by that button.
        XCTAssertTrue(waitForBudgetHome(app), "expected the budget home screen after login")
    }

    @MainActor
    func testLoginWithWrongPasswordShowsAnError() throws {
        guard let email = ProcessInfo.processInfo.environment["UITEST_EMAIL"] else {
            throw XCTSkip("Set UITEST_EMAIL to run this test against a seeded account.")
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
        passwordField.typeText("definitely-the-wrong-password-1!")

        app.buttons["loginButton"].tap()

        XCTAssertTrue(app.staticTexts["loginErrorMessage"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["budgetMenuButton"].exists)
    }
}
