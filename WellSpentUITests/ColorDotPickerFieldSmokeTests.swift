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
        let app = XCUIApplication()
        try signInToEmptyAccount(app)

        createBudget(app, name: "UITest ColorDotPicker \(Int(Date().timeIntervalSince1970))", paymentMethodName: "UITest Card")

        // Overview/Plan navigation rework: Transactions is no longer its own
        // bottom tab — it's a sub-tab inside Home (the bottom tab renamed
        // once "Overview" became a sub-tab's own name instead).
        app.tabBars.buttons["Home"].tap()
        app.buttons["Transactions"].tap()

        // "+" is now a Menu (Stage 2 merged Variable+Fixed into one list,
        // so there's no sub-picker left to say which kind "+" means).
        app.buttons["addTransactionButton"].tap()
        app.buttons["addVariableTransactionMenuItem"].tap()

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

        // Targeted by identifier, not by its "Cancel" label: the button is now
        // an icon whose label is localized, and this suite has to keep working
        // in whatever locale the simulator is running.
        app.navigationBars.buttons["sheetCancelButton"].tap()

        // Cleanup: delete the budget so the test leaves no orphan data behind.
        deleteCurrentBudget(app)
    }
}
