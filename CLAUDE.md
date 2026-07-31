# CLAUDE.md — WellSpent-iOS

Native iOS (SwiftUI) client for WellSpent. Consumes the same ConnectRPC API as `WellSpent-web`, via the same `wellspent.v1` proto contracts published by `WellSpent-proto`.

`WellSpent.xcodeproj` lives directly at the repo root, alongside `WellSpent/` (app sources), `WellSpentTests/`, `WellSpentUITests/`, `Packages/WellSpentAPI/`, and `buf.gen.yaml` — same flat layout as the other three sub-repos. (Xcode's project-creation dialog defaults to nesting everything one level deeper, inside a `<ProductName>/` subfolder; that extra nesting was flattened out during initial setup.)

## Commands

Run all of these from the repo root (`WellSpent-iOS/`):

```bash
make generate     # buf generate — pulls proto from BSR, generates Swift into Packages/WellSpentAPI/Sources/WellSpentAPI/Gen/
swift build --package-path Packages/WellSpentAPI   # fast standalone compile check of just the generated + client layer
swift test --package-path Packages/WellSpentAPI    # WellSpentAPI's own unit tests (AuthInterceptor etc.)

xcodebuild -list -project WellSpent.xcodeproj                                          # confirm scheme name
xcrun simctl list devices available                                                    # pick an installed simulator
xcodebuild -scheme WellSpent -destination 'platform=iOS Simulator,name=<device>' build
xcodebuild test -scheme WellSpent -destination 'platform=iOS Simulator,name=<device>' -only-testing:WellSpentTests
xcodebuild test -scheme WellSpent -destination 'platform=iOS Simulator,name=<device>' -only-testing:WellSpentUITests   # needs a live WellSpent-backend + UITEST_EMAIL/UITEST_PASSWORD env vars for the login/logout flows
```

If `xcodebuild`/`xcrun` says "requires Xcode" (Command Line Tools active instead of full Xcode), prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Setup (new contributor)

1. Install `buf`: `brew install bufbuild/buf/buf`
2. `cd WellSpent-iOS && make generate` — confirms BSR auth works for Swift codegen before anything else
3. Open `WellSpent.xcodeproj` in Xcode
4. `cd ../../WellSpent-backend && make secrets-decrypt ENV=dev && make run` — API on `http://localhost:8080`; no CORS setup needed, CORS doesn't apply to native `URLSession`
5. Run the app in Simulator (⌘R) — Debug builds point at `http://localhost:8080` by default (`INFOPLIST_KEY_APIBaseURL` in the Debug build configuration)

## Architecture

- **UI**: SwiftUI only (no UIKit). Min deployment target iOS 17.0. **iOS/iPadOS only** — `SUPPORTED_PLATFORMS` is explicitly `"iphoneos iphonesimulator"` and `TARGETED_DEVICE_FAMILY` is `"1,2"` on every build configuration. Xcode's "App" template defaults new projects to multiplatform (adds `macosx`/`xros` + a "My Mac"/Vision Pro destination) unless you restrict destinations at creation time — this bit us once already (`.keyboardType(_:)`/`UIKeyboardType` are UIKit-only and don't exist on macOS, so a macOS destination fails to compile with a confusing type-checker error). If Xcode ever re-offers a "My Mac" or Vision Pro destination in the scheme picker, the project settings have regressed — re-check `SUPPORTED_PLATFORMS`/`TARGETED_DEVICE_FAMILY` in `project.pbxproj` before debugging anything else.
- **State/architecture**: MVVM using the `@Observable` macro (Observation framework) — no third-party state management. Every screen has a paired `View` + `@Observable @MainActor ViewModel`, dependencies (the ConnectRPC client) injected via `init`, not read from environment inside the view model.
- **Networking**: [connect-swift](https://github.com/connectrpc/connect-swift) — the Swift member of the same ConnectRPC family as `connect-es` (web) and `connect-go` (backend). Generated via `buf generate` against `buf.build/bewellspent/wellspent`, same BSR module the other two repos consume.
- **Concurrency**: Swift Concurrency (async/await) throughout. Note: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set project-wide (Xcode's new default for SwiftUI apps) — plain logic types with no UI affinity (`JWT`, `KeychainTokenStore`, `FeatureFlags`, `APIEnvironment`) are explicitly marked `nonisolated` so they stay callable from background contexts (e.g. the networking layer's `TokenProvider` closure, which connect-swift may invoke off the main thread).
- **Local storage**: **Keychain** for the JWT only (`Auth/KeychainTokenStore.swift`, raw `Security` framework, no third-party wrapper). No local database — the app is a thin client, same as the web app; everything else is fetched live. `UserDefaults`/`@AppStorage` for simple prefs once Phase 2 needs them (locale/currency/view-mode) — not present yet, since nothing in the Auth-only phase consumes them (would be dead code).
- **Testing**: **Swift Testing** (`@Test`/`#expect`) for unit tests, **XCUITest** for a handful of end-to-end smoke flows only.

## Proto codegen (`Packages/WellSpentAPI`)

Generated Swift code is **not committed** (gitignored, same policy as `src/gen/` in web and `gen/` in backend) — always run `make generate` after cloning or after any proto change.

`Packages/WellSpentAPI` is a **local Swift package**, not files dropped directly into the app target. Reason: Xcode's `.xcodeproj` tracks file references explicitly for anything outside a synchronized folder group; regenerating proto code that adds/removes files would otherwise mean manually re-adding references in Xcode every time. A local SPM package auto-globs its `Sources/` folder instead — regeneration is just "the file tree changed," no project-file surgery. The app target depends on `WellSpentAPI` (plus its transitive `Connect`/`SwiftProtobuf` products, added as **direct** package dependencies too — see note below) and never touches `Gen/` directly.

- `buf.gen.yaml` (repo root) — Swift plugins `buf.build/apple/swift` + `buf.build/connectrpc/swift`, output to `Packages/WellSpentAPI/Sources/WellSpentAPI/Gen/`
- `Packages/WellSpentAPI/Sources/WellSpentAPI/Client/` — hand-written wrapper (not generated, not gitignored):
  - `APIClient.swift` — `makePublicClient(baseURL:)` / `makeAuthenticatedClient(baseURL:tokenProvider:onUnauthenticated:)`, mirrors web's `publicTransport` / `createTransport(token)` in `src/lib/api/client.ts`
  - `AuthInterceptor.swift` — attaches `Authorization: Bearer <token>`, reports 401s back to the app
  - `TokenProvider.swift` — `TokenProvider`/`UnauthenticatedHandler` typealiases (plain `@Sendable` closures, not a protocol — lets the token source be a synchronous Keychain read with no actor-isolation ceremony)
  - `@_exported import Connect` / `@_exported import SwiftProtobuf` in `APIClient.swift` — lets app code reference `ProtocolClient`, `ConnectError`, `Code`, and the `.with { }` builder pattern via just `import WellSpentAPI`

**Why the app target also directly links `Connect` and `SwiftProtobuf`, not just `WellSpentAPI`:** `@_exported import` re-exports symbols at the *source* level, but under Xcode's newer "debug dylib" test-hosting mechanism, that alone isn't enough for the *linker* to find them — you'll see `Undefined symbols` for `Connect.ProtocolClient` etc. at `xcodebuild test` time even though a plain `xcodebuild build` succeeds. Fix: both `WellSpent` and `WellSpentTests` targets have explicit direct package product dependencies on `Connect` and `SwiftProtobuf` (same resolved versions `WellSpentAPI` already pulls in), not just on `WellSpentAPI`. If a future `swift test`/`xcodebuild build` (not `test`) starts failing with similar undefined-symbol errors after adding a new generated-type usage in a new file, this is almost certainly the same class of issue — check whether the target needs the same direct dependency.

## Auth flow (Phase 1)

- `WellSpentApp.swift` owns the single `SessionStore` (`@Observable`, `@MainActor`) for the app's lifetime, injected via `.environment(session)`.
- `SessionStore` mirrors web's `AuthContext` + `TransportProvider`: `publicClient` (unauthenticated, for Register/Login/ListCountries) and `authenticatedClient` (built fresh on login, torn down on logout).
- **No proactive token refresh.** `AuthService.RefreshToken` exists on the proto/backend and is available in the generated client, but nothing calls it — this matches the web app's actual current behavior (it has the same RPC available and also never calls it). On expiry, both platforms just force a re-login. If this ever changes, change it on both platforms together or note explicitly why they diverge.
- `RootView` switches between the login/register flow and `BudgetListView` based on `session.isAuthenticated`, and calls `session.refreshAuthenticationState()` on `scenePhase == .active` — the Swift equivalent of web's `visibilitychange` expiry check.
- Google OAuth: `GoogleAuthButton` is rendered disabled behind `FeatureFlags.googleAuthEnabled` (reads the `FEATURE_GOOGLE_AUTH` process environment variable, off by default) — matches web's posture exactly. Real `GetGoogleAuthURL`/`ExchangeGoogleCode` wiring (needs its own Google Cloud OAuth client + `ASWebAuthenticationSession`) is out of scope until a later phase.

## Budget flow (Phase 2A / 2B-1 / 2B-2 / 2B-3 / 2C-1)

Phase 2A covers budgets/periods, people, and income sources; 2B-1 adds categories and payment methods; 2B-2 adds Variable transactions; 2B-3 adds Fixed expenses + mark-paid/unmark; 2C-1 adds expense allocations, filling in the real Plan tab. See the roadmap below for what's still ahead (Expense Overview, profile/account settings).

- `WellSpent/Budget/` is the feature folder, one subfolder per management panel (`budgetList/`, `peoplePanel/`, `incomePanel/`, `categoriesPanel/`, `paymentMethodsPanel/`, `transactionsPanel/`), same layout convention as web's `src/components/budget/`.
- **`BudgetListView`/`BudgetListViewModel`** replaced the Phase 1 `HomePlaceholderView`/`HomeViewModel` stand-in — it now owns the top-level `GetMe` call (verify-email banner + the user's `currency`/`language`, used for money formatting everywhere downstream) alongside `ListBudgetProfiles`.
- **`BudgetDetailView` is the adaptive navigation shell**, not content itself: a bottom `TabView` on iPhone (`.compact` horizontal size class), a `NavigationSplitView` sidebar on iPad (`.regular`) — `BudgetSection` (`.plan`/`.transactions`/`.manage`) drives both. This collapses web's two independent nav layers (top tabs for Plan/Transactions/... *and* a separate sidebar/drawer for Income/Savings/Payment Methods/Categories/People) into one, since iOS has no good native equivalent of a persistent second nav rail alongside a tab bar. All three tabs are now real: Plan (allocations, 2C-1), Transactions (Variable + Fixed, 2B-2/2B-3), Manage (People/Income/Categories/Payment Methods). Default selected tab is `.manage` — revisit once Expense Overview (2C-2) adds a second view inside Plan.
- **`BudgetDetailViewModel.loadPeriod()` runs at the shell level** (`BudgetDetailView`'s own `.task`), not inside `BudgetManageView` — the Transactions tab needs `currentPeriod.id` for `budget_period_id` regardless of which tab loads first, so period loading can't be gated behind the user happening to open Manage. The Transactions tab shows a `ProgressView` until `currentPeriod` resolves.
- **Delete-budget dismiss must be passed down explicitly, not re-declared.** `BudgetManageView` sits inside its own nested `NavigationStack` (so People/Income/Categories/Payment Methods pushes don't disturb the other tabs), so a locally-declared `@Environment(\.dismiss)` there would only pop within that inner stack. `BudgetDetailView` captures `@Environment(\.dismiss)` at its own outer scope and passes a combined `dismissParent` closure (notify the parent list + actually dismiss) down instead. Apply the same pattern to any future tab/section that needs to close the whole budget detail screen from inside its own nested stack.
- **Removing a person** only prompts for a replacement when they have income sources attributed to them (`PersonReplacement.needsReplacement(person:incomeSources:)`, kept as a pure function in its own file so it's unit-testable without SwiftUI). **Known gap**: this doesn't check payment-method attribution even though Payment Methods now exist (2B-1) — `RemoveBudgetPersonRequest.replacement_payment_method_id` is never populated by the iOS client. Soft-delete (`is_active = false`, not a hard row delete) likely means this isn't a hard backend requirement the way `DeleteCategory`/`DeletePaymentMethod`'s replacement *is* (confirmed required via a live 401/`invalid_argument` check during 2B-1), but it should be verified and closed before Phase 3 touches People again.
- **Categories and payment methods always require a replacement on delete** — confirmed directly against the live backend during 2B-1 (`DeleteCategory`/`DeletePaymentMethod` both reject `replacement_id`/`replacement_payment_method_id` left at their zero value), unlike removing a person, where it's conditional. So `DeleteCategoryView`/`DeletePaymentMethodView` always show the picker; no `needsReplacement`-style check for either.
- **Payment type is immutable after creation** — `AddPaymentMethodView` has a type picker, `EditPaymentMethodView` doesn't (name/alias/color only), same Create/Edit-view split used for budgets in 2A (fields genuinely differ between add and edit, so two view models rather than one shared `Mode` enum like income/categories).
- **`transaction_type_id`/`transaction_frequency_id` are raw `int32` FKs on the wire, not proto enums** — their values (Fixed=1/Variable=2; One-off=1/Weekly=2/Bi-weekly=3/Monthly=4/Yearly=5) come from the seed order in `WellSpent-backend/internal/db/migrations/000001_init_schema.sql`, not a generated type, so every place that uses them has a doc comment pointing back at that migration. `TransactionsViewModel.variableTypeID`/`FixedExpensesViewModel.fixedTypeID` are the one source of truth for `2`/`1`; `AddEditTransactionViewModel` derives `transactionFrequencyID` from the `recurring` toggle (`recurring ? 4 : 1`).
- **Spent/Received sign convention** (`docs/features/negative-positive-transactions.md`): the Variable add/edit form always takes a positive amount plus a segmented Spent/Received toggle; `amount >= 0` = Spent (red, `-` prefix), `amount < 0` = Received (green, `+` prefix). `TransactionAmountFormatting.swift` holds this as pure, unit-tested logic — never inline a sign check in a view. **Fixed expenses have no sign flip** — always a plain expense, shown via `MoneyFormatting.format` directly, not `TransactionAmountFormatting`.
- **Not yet ported from web, deliberately deferred**: "Spent only"/"Excluded only" filters; the exclude toggle doesn't special-case the system "Income" category the way web's `isTransactionExcluded` helper does; Fixed expense payment-plan fields (`end_date`/`total_payments` — web's bidirectional end-date↔total-payments computation); "not due yet" placeholder rows for active Fixed templates whose anchor date hasn't spawned a transaction yet this period (lower priority since `CreateFixedExpenseResponse` returns the spawned transaction directly, so a freshly created template shows up immediately in the common case). All real web behaviors, just not in scope yet — note before assuming totals/filtering/Fixed-expense scheduling fully match web.
- **Fixed expenses live inside the Transactions tab, not a separate Manage panel** — mirrors web exactly (`TransactionsPanel.tsx`'s Fixed/Variable toggle over spawned `Transaction` rows, not a standalone `FixedExpense` list). `TransactionsListView` owns a `TransactionKind` (`.variable`/`.fixed`) segmented picker; `FixedExpensesListView` is the Fixed sub-view, each with their own toolbar "+" that only contributes to the shared toolbar while its content is actually on screen (SwiftUI composes `.toolbar` modifiers from whichever descendant view is currently in the hierarchy — no manual coordination needed since only one of the two is ever mounted at a time).
- **Mark-paid amount propagation to the template is entirely backend-side** — confirmed live: marking a Fixed transaction paid with an amount different from `planned_amount` automatically updates the linked `FixedExpense.planned_amount`. The iOS client only calls `MarkTransactionAsPaid`; never a follow-up `UpdateFixedExpense`.
- **`anchor_date` is the only date the user picks**; `day_of_month`/`day_of_week` are always derived from it client-side (`FixedExpenseScheduling.swift`, pure + unit-tested) since `CreateFixedExpenseRequest`/`UpdateFixedExpenseRequest` carry them as plain non-optional `int32` fields with no "compute this yourself" flag.
- **Established `Shared/` label/formatting/input helpers** (all `nonisolated enum`s with static functions, mirroring web's small formatting hooks): `Money+Formatting.swift`, `MoneyInput.swift` (shared `parseAmount`/`formatForEditing` for every money text field), `TransactionAmountFormatting.swift` (home to `sum(_:)`, the shared nanos-carry addition logic — handles both overflow and underflow for negative amounts — used by `totalDisplayText` and by `ExpensePlanCalculations`), `FixedExpenseScheduling.swift`, `ExpensePlanCalculations.swift` (2C-1, below), `BudgetCycleLabel.swift`, `BudgetRoleLabel.swift`, `IncomeTypeLabel.swift`, `RecurringTypeLabel.swift`, `PaymentTypeLabel.swift`. Reuse this pattern for any new proto enum/parsing/derivation rule rather than inlining in a view or view model. `PresetColors.all` (a fixed hex list, no `Color(hex:)` parser) is the shared source for every optional-color picker (people, categories, payment methods).
- **Expense Plan tab (2C-1)** — `WellSpent/Budget/expensePlanPanel/`. A per-category planned total (`ExpensePlanCalculations.plannedTotal`, pure + unit-tested, mirrors web's `getCatPlanned`): the Savings system category always sums `SavingsSource.amount`; every other category sums `ExpenseAllocation.plannedAmount` across people, and only if that's zero falls back to the sum of the current period's Fixed-type transactions' `plannedAmount` for that category — allocations and the fixed fallback are never combined. Categories are visible only if that total is nonzero; visible ones sort by planned total descending (`docs/features/category-list-order.md`). **Exclusion (`is_excluded`) does not affect planned totals** — confirmed live (excluding a Fixed transaction still counts its `plannedAmount` toward the category total); it only matters for Overview's actuals (2C-2, not built yet).
- **Allocation edits are per (category, person), not a single form** — tapping a category row opens `AllocateCategoryView`, one amount field per `BudgetPerson`, prefilled from any existing allocation. `AllocateCategoryViewModel.computeChanges` is the pure diff: a nonblank valid amount becomes an `UpsertExpenseAllocation` call, a row that had an allocation but is now blank becomes `DeleteExpenseAllocation`, and a row that was already blank stays untouched (no allocation created for a still-zero row). Same "sheet computes the value, parent view model performs the network call" split as `MarkAsPaidView` — `ExpensePlanViewModel.applyAllocationChanges` is the one that actually calls the RPCs and reloads.
- **Adding a not-yet-visible category to the plan** uses a flat picker sheet (`AddPlanCategoryView`, categories minus already-visible ones) rather than nesting a second sheet inside a sheet — selecting one dismisses the picker and `ExpensePlanView` presents `AllocateCategoryView` for it next. This replaces web's free-text "pin a category" Autocomplete with a simpler native equivalent.
- **Not yet ported from web, deliberately deferred**: the Expense Overview tab (actual vs. planned, chart, collapsible per-person actuals, overspend `+$X` chip) — see Roadmap, 2C-2; "not due yet" fixed-expense placeholder rows in the Plan total (same deferral as 2B-3, carried over — only current-period Fixed transactions count toward the fallback, not templates that haven't spawned one yet).
- **Every `View` struct has a `#Preview`** — a running requirement now, not just a 2B-3 cleanup. Views that hit the network use a throwaway unreachable `ProtocolClient` (`http://localhost:1`, same as the test suite's convention) so the canvas still renders the loading/empty state; views driven directly by init params (edit forms, delete/mark-paid pickers) get realistic sample proto values so they render fully populated.
- App version is now surfaced (`BudgetListView`'s footer, reading `Bundle.main.infoDictionary["CFBundleShortVersionString"]`) — bump `MARKETING_VERSION` in the **`WellSpent` app target's** Debug/Release configs only (not the test targets) per the existing patch/minor/major convention, now that there's a UI surface for it. (2B-1/2B-2 shipped without a bump — an oversight caught and corrected in 2B-3; don't repeat it.)

## Testing

- **Swift Testing**, one `@Suite` per type, in `WellSpentTests/` (app target logic) and `Packages/WellSpentAPI/Tests/WellSpentAPITests/` (networking layer). Covers: JWT decode/expiry edge cases, Keychain round-trips (real Simulator Keychain — works fine under `xcodebuild test`, each test uses a unique service name to avoid cross-test interference), `AuthInterceptor` header injection and 401 handling (constructed `HTTPRequest`/`ResponseMessage` values directly, no network mocking needed), view model validation + error-code-to-message mapping, `SessionStore` state transitions.
- Deliberately **not** unit tested: SwiftUI view bodies (no assertion value without a UI-test harness) and thin one-line pass-throughs to generated RPC methods.
- **XCUITest** smoke flows in `WellSpentUITests/`: `LoginSmokeTests` (valid + wrong-password), `RegisterSmokeTests` (fresh timestamp-suffixed email — no seeded account needed), `LogoutSmokeTests` (log out, then relaunch *without* the reset flag to prove the Keychain token was actually cleared, not just in-memory state), `BudgetSmokeTests` (create a budget, add a person, add an income source, then delete the budget as cleanup so repeated runs don't leave orphan data on the real backend). Login/Logout/Budget tests need a seeded account: `export UITEST_EMAIL=... UITEST_PASSWORD=...` before running. All need `WellSpent-backend` running locally.
- The app supports a `-uiTestResetSession` launch argument (checked in `WellSpentApp.init`) that clears the Keychain token before `SessionStore` restores a session — every UI test starts from a known logged-out state instead of inheriting whatever the Simulator's Keychain has from a previous run.
- Accessibility identifiers are set explicitly on every interactive element and screen-level container (not inferred from label text) — i18n will change label text later, identifiers won't.

## Version bump

Wired up as of Phase 2A: `MARKETING_VERSION` in the **`WellSpent` app target's** Debug/Release build configs (`WellSpentTests`/`WellSpentUITests` configs are untouched — their version number has no user-facing meaning), read at runtime via `Bundle.main.infoDictionary["CFBundleShortVersionString"]` and shown in `BudgetListView`'s footer. Bump it for every feature going forward, same patch/minor/major convention as the other repos.

## Git workflow

Same convention as the other sub-repos: work happens on `develop`, never directly on `main`.

```bash
git checkout develop   # or: git checkout -b develop, if it doesn't exist yet locally
git add WellSpent/... Packages/WellSpentAPI/Package.swift Packages/WellSpentAPI/Sources/WellSpentAPI/Client/... Packages/WellSpentAPI/Tests/...
git commit -m "feat: meaningful description of what changed"
git push origin develop
```

(No PR/auto-merge automation set up on this repo yet — add `gh pr create --base main --head develop ... && gh pr merge develop --auto --merge` here once CI exists for this repo, matching the other three.)

## Generated files — do not edit

`Packages/WellSpentAPI/Sources/WellSpentAPI/Gen/` — generated by `make generate` from `buf.build/bewellspent/wellspent`. Gitignored.

## Roadmap

"Phase 2 — core budget loop" was too large for one confirmed slice (same reasoning as Phase 0+1), so it's split further:

- **Phase 2A (done)** — budgets/periods, people, income sources. See "Budget flow (Phase 2A / 2B-1)" above.
- **Phase 2B-1 (done)** — categories, payment methods. Same section above.
- **Phase 2B-2 (done)** — Variable transactions (create/edit/delete, Spent/Received sign flip, exclude toggle). Fills in the real Transactions tab. No filters ("Spent only"/"Excluded only") yet — see "Budget flow" above.
- **Phase 2B-3 (done)** — Fixed expense templates (`FixedExpense` CRUD) + mark-paid/unmark on their spawned transactions, via a Variable/Fixed picker inside the Transactions tab. Payment-plan fields (`end_date`/`total_payments`) and "not due yet" placeholder rows deliberately deferred — see "Budget flow" above.
- **Phase 2C-1 (done)** — expense allocations (`ExpenseAllocation` CRUD), filling in the real Plan tab: category list with planned totals, per-person allocate sheet, add-category picker, income/committed/remainder footer. See "Budget flow" above.
- **Phase 2C-2 (not started)** — Expense Overview tab (actual vs. planned, chart, collapsible per-person actuals, overspend indicators). Adds a Plan/Overview picker inside the Plan tab, mirroring the `TransactionKind` picker pattern from 2B-3.
- **Phase 2C-3 (not started)** — profile/account settings (profile fields, change password, delete account) — the User/Auth-service equivalent of web's Settings pages, not a Budget-service feature like the rest of 2C.
- **Phase 3 (not started)** — savings, invites, alerts.
- **Phase 4 (not started)** — Plaid, transaction review, tiers.

Each phase should update this file's Architecture/Testing sections as new patterns get established, the same way `WellSpent-web/CLAUDE.md` accumulated its "Component composition" and "Mobile + desktop support" sections over time.
