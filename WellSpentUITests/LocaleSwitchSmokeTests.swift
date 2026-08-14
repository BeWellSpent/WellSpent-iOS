import XCTest

/// Proves that the in-app language preference actually reaches
/// `Text("literal")` in a view body.
///
/// `AppLanguageStore` caches the account's language in `UserDefaults` under
/// `"appLanguage"`, and `WellSpentApp` turns that into
/// `.environment(\.locale:)` at the `WindowGroup` root. Passing
/// `-appLanguage es` as a launch argument sets exactly that `UserDefaults`
/// key (the standard `NSArgumentDomain` behaviour), so this reproduces a
/// Spanish-speaking account on an English device — which is precisely the
/// configuration the language switch is *for*, and the one that was never
/// verified when multi-language shipped in v1.21.0.
///
/// The login screen is the subject because it's reachable with no backend
/// and its title goes through the plain-literal path
/// (`LoginView`'s `Text("Log In")`), which is the pattern used by 148 call
/// sites across 48 files.
final class LocaleSwitchSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testChosenLanguageTranslatesPlainTextLiterals() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestResetSession", "-appLanguage", "es"]
        app.launch()

        // Wait on an identifier, not a label — identifiers don't move when
        // the language does.
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 10))

        let spanish = app.staticTexts["Iniciar sesión"]
        let english = app.staticTexts["Log In"]

        XCTAssertTrue(
            spanish.exists,
            "Login screen still rendered English with appLanguage=es — "
                + "environment(\\.locale:) is not redirecting LocalizedStringKey lookup. "
                + "English 'Log In' present: \(english.exists)"
        )
    }
}
