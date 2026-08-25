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

/// Opens the ☰ menu and drills into the Manage panels, where People, Income,
/// Categories, Payment Methods and the rest live.
func openManagePanels(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
    guard openBudgetMenu(app, timeout: timeout) else { return false }
    let manageLink = app.buttons["manageBudgetLink"]
    guard manageLink.waitForExistence(timeout: 5) else { return false }
    manageLink.tap()
    return true
}

/// Waits for the budget home screen to be showing an actual budget — the tab
/// bar only exists once a profile has loaded. Replaces the old
/// `addBudgetButton` wait, which now only appears when there is *no* budget.
func waitForBudgetHome(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
    app.tabBars.firstMatch.waitForExistence(timeout: timeout)
}
