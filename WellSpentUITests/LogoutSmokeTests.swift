import XCTest

/// Requires a seeded test account — set `UITEST_EMAIL`/`UITEST_PASSWORD`.
/// The seeded account must be able to get past the email-verification gate —
/// either genuinely verified, or marked exempt with
/// `UPDATE users SET account_type = 'test' WHERE email = '<UITEST_EMAIL>';`
/// (see WellSpent-backend migration 000045). Without that, login succeeds but
/// lands on the gate instead of the budget list.
final class LogoutSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLogoutReturnsToLoginAndClearsTheStoredToken() throws {
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
        XCTAssertTrue(app.buttons["logoutButton"].waitForExistence(timeout: 10))

        app.buttons["logoutButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["loginView"].waitForExistence(timeout: 10))

        // Relaunch *without* the reset flag — if the Keychain token were still
        // present, SessionStore would restore an authenticated session and
        // we'd land back on the home screen instead of Login.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["loginView"].waitForExistence(timeout: 10))
    }
}
