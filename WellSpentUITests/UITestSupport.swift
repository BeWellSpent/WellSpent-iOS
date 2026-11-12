import XCTest

/// iOS offers to save a newly-used password to the Keychain/Password Manager
/// right after a successful login or registration ("Save Password? Not Now /
/// Save"). It's a system alert, not part of our UI, but it steals focus and
/// blocks every subsequent tap until dismissed — call this right after any
/// action that logs the user in.
func dismissSavePasswordPromptIfPresent(_ app: XCUIApplication) {
    let notNow = app.buttons["Not Now"]
    if notNow.waitForExistence(timeout: 3) {
        notNow.tap()
    }
}

/// Opens the menu that holds everything outside the four real bottom tabs —
/// period switching, the manage panels, settings, help, log out.
///
/// Since issue #60 the budget itself is the home screen, so there is no budget
/// list to navigate through and no "Manage" tab. Tests that used to tap
/// `periodRow_…` and then a `…NavLink` go through here instead.
///
/// Targets the **last** tab-bar button by index rather than its "More" label:
/// this suite has a locale-switching test, and the label is translated.
func openBudgetMenu(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
    guard waitForBudgetHome(app, timeout: timeout) else { return false }
    let tabs = app.tabBars.buttons
    guard tabs.count > 0 else { return false }
    tabs.element(boundBy: tabs.count - 1).tap()
    return true
}

/// Opens the More sheet, where People, Income, Categories, Payment Methods
/// and the rest are listed directly.
func openManagePanels(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
    openBudgetMenu(app, timeout: timeout)
}

/// Waits for the budget home screen to be showing an actual budget — the tab
/// bar only exists once a profile has loaded. Replaces the old
/// `addBudgetButton` wait, which now only appears when there is *no* budget.
func waitForBudgetHome(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
    app.tabBars.firstMatch.waitForExistence(timeout: timeout)
}

/// Walks the setup wizard (People → Payment methods → Income → Savings) that
/// follows "Create budget", skipping every step. Pass `paymentMethodName` to
/// add one first: adding a transaction is blocked until the budget has a
/// payment method (transaction-prerequisites).
///
/// Each skip waits for that step's own field rather than the shared
/// `setupSkipButton`, which would still match mid-transition and double-tap.
func finishBudgetSetup(_ app: XCUIApplication, paymentMethodName: String? = nil) {
    func anchor(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    func skip(after anchorID: String) {
        XCTAssertTrue(anchor(anchorID).waitForExistence(timeout: 10), "expected setup step \(anchorID)")
        app.buttons["setupSkipButton"].tap()
    }

    skip(after: "setupPersonNameField")

    if let paymentMethodName {
        let nameField = app.textFields["setupPaymentMethodNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "expected the Payment Methods step")
        nameField.tap()
        nameField.typeText(paymentMethodName)
        app.buttons["setupAddPaymentMethodButton"].tap()
        XCTAssertTrue(app.staticTexts[paymentMethodName].waitForExistence(timeout: 10), "expected the payment method to be added")
    }
    skip(after: "setupPaymentMethodNameField")
    skip(after: "setupIncomeNameField")

    XCTAssertTrue(
        anchor("setupSavingsNameField").waitForExistence(timeout: 10)
            || anchor("setupSavingsNeedsPaymentMethod").exists,
        "expected the Savings step"
    )
    app.buttons["setupSkipButton"].tap()
}

/// An account with no budget lands on the empty state instead of the tab bar,
/// and either one proves the login worked.
func waitForAuthenticatedLanding(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
    // Polls both states instead of waiting on one: a long failed wait on the
    // tab bar of a no-budget account has crashed the test runner.
    let empty = app.descendants(matching: .any)["emptyBudgetsState"]
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if app.tabBars.firstMatch.exists || empty.exists { return true }
        Thread.sleep(forTimeInterval: 0.5)
    }
    return false
}

/// Launches logged out and signs in as the seeded `UITEST_EMAIL` account.
/// Skips when the credentials aren't set.
func signInSeededUser(_ app: XCUIApplication) throws {
    guard let email = ProcessInfo.processInfo.environment["UITEST_EMAIL"],
          let password = ProcessInfo.processInfo.environment["UITEST_PASSWORD"] else {
        throw XCTSkip("Set UITEST_EMAIL / UITEST_PASSWORD to run this test against a seeded account.")
    }

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
    XCTAssertTrue(waitForAuthenticatedLanding(app), "expected to be logged in")
}

/// Deletes the open budget through the manage panels, ending on the no-budget
/// empty state.
func deleteCurrentBudget(_ app: XCUIApplication) {
    XCTAssertTrue(openManagePanels(app), "expected the ☰ menu to open the manage panels")
    let detailMenu = app.buttons["budgetDetailMenu"]
    XCTAssertTrue(detailMenu.waitForExistence(timeout: 5))
    detailMenu.tap()
    let deleteItem = app.buttons["Delete Budget"]
    XCTAssertTrue(deleteItem.waitForExistence(timeout: 10), "expected the Delete Budget menu item")
    deleteItem.tap()
    let confirm = app.buttons["Delete"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 10), "expected the delete confirmation")
    confirm.tap()
    XCTAssertTrue(app.buttons["addBudgetButton"].waitForExistence(timeout: 20), "expected the empty state after deleting")
}

/// An account may own one budget, so tests that create theirs need none to
/// exist. Clears one left behind by an earlier failed run.
func signInToEmptyAccount(_ app: XCUIApplication) throws {
    try signInSeededUser(app)
    if app.tabBars.firstMatch.exists {
        deleteCurrentBudget(app)
    }
}

/// From the empty state: creates a budget and walks the setup wizard.
func createBudget(_ app: XCUIApplication, name: String, paymentMethodName: String? = nil) {
    let addButton = app.buttons["addBudgetButton"]
    XCTAssertTrue(addButton.waitForExistence(timeout: 10))
    addButton.tap()

    let nameField = app.textFields["budgetNameField"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 15))
    nameField.tap()
    nameField.typeText(name)
    app.buttons["createBudgetButton"].tap()

    finishBudgetSetup(app, paymentMethodName: paymentMethodName)
    XCTAssertTrue(waitForBudgetHome(app), "expected the budget home screen after setup")
}
