import XCTest

/// Confirms a modal sheet presents the shared chrome from `Shared/SheetChrome.swift`:
/// a "✕" in place of a "Cancel" button, which dismisses (issue #57).
///
/// The budget setup sheet is the site exercised because it is reachable
/// immediately after login, without a budget, a period, or a payment method —
/// every other sheet sits behind at least one of those.
///
/// Requires a seeded account (`UITEST_EMAIL`/`UITEST_PASSWORD`) that can get
/// past the email-verification gate, same as `BudgetSmokeTests`. The account
/// must own no budget, since the "+" that opens this sheet is hidden once one
/// exists.
final class SheetChromeSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSheetShowsDismissingCloseIconInsteadOfCancelButton() throws {
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

        // Manage is reachable whenever a budget exists, unlike addBudgetButton,
        // which only appears for an account that has none. Any sheet exercises
        // the shared chrome equally well.
        //
        // The ☰ drawer itself is deliberately not the subject here: it is not a
        // sheet, so its close button sits in its own header rather than a
        // navigation bar, and the assertions below are about navigation-bar
        // chrome specifically.
        XCTAssertTrue(openManagePanels(app), "expected the ☰ menu to open the manage panels")

        // The sheet is up once its content is on screen.
        XCTAssertTrue(app.buttons["peopleNavLink"].waitForExistence(timeout: 5))

        let closeButton = app.navigationBars.buttons["sheetCancelButton"]
        XCTAssertTrue(closeButton.exists, "sheet should carry the shared ✕ button")

        // The label is what VoiceOver announces — the glyph must not be
        // presented as an unlabelled button just because its title is hidden.
        XCTAssertEqual(closeButton.label, "Cancel")

        // Deliberately not asserted: that no button *titled* "Cancel" remains.
        // XCUITest matches on the accessibility label, which the ✕ still carries
        // by design, so such an assertion would fail on a correct implementation
        // — whether the title is drawn is not observable from here.

        closeButton.tap()
        XCTAssertTrue(app.buttons["budgetMenuButton"].waitForExistence(timeout: 5), "✕ should dismiss the sheet")
        XCTAssertFalse(app.buttons["peopleNavLink"].exists)
    }
}
