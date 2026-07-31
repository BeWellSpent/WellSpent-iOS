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
