import XCTest

/// No seeded account needed — generates a fresh, timestamp-unique email each
/// run so repeated CI runs never collide with the backend's duplicate-email
/// check.
final class RegisterSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRegisterWithFreshEmailReachesAuthenticatedScreen() throws {
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
        emailField.typeText("ios-uitest-\(Int(Date().timeIntervalSince1970))@example.com")

        let passwordField = app.secureTextFields["registerPasswordField"]
        passwordField.tap()
        passwordField.typeText("Valid1Password!")

        app.buttons["registerButton"].tap()
        dismissSavePasswordPromptIfPresent(app)

        // A brand-new email/password account is never pre-verified (only
        // Google and Apple sign-ups are), so registration lands on the
        // verification gate, not the budget list.
        //
        // This address is invented at run time, so it can't be seeded as an
        // account_type = 'test' exemption the way the other smoke tests'
        // UITEST_EMAIL account is — reaching the gate *is* the correct
        // outcome here, and asserting it is what proves the block works for
        // a genuinely fresh signup.
        XCTAssertTrue(app.buttons["resendVerificationButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["verifyGateLogoutButton"].exists)
        XCTAssertFalse(app.buttons["budgetMenuButton"].exists, "an unverified account must not reach the budget")
    }
}
