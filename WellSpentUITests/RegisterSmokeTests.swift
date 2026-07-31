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
        // Google sign-ups are), so the verify-email banner should appear
        // alongside the authenticated placeholder screen.
        XCTAssertTrue(app.buttons["logoutButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["resendVerificationButton"].waitForExistence(timeout: 10))
    }
}
