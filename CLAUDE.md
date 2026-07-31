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
- `RootView` switches between the login/register flow and `HomePlaceholderView` based on `session.isAuthenticated`, and calls `session.refreshAuthenticationState()` on `scenePhase == .active` — the Swift equivalent of web's `visibilitychange` expiry check.
- `HomePlaceholderView` (`App/`) stands in for the real budgets list until Phase 2. It calls `GetMe` to prove the authenticated client actually works end-to-end, and shows `VerifyEmailBannerView` when `user.isVerified == false`.
- Google OAuth: `GoogleAuthButton` is rendered disabled behind `FeatureFlags.googleAuthEnabled` (reads the `FEATURE_GOOGLE_AUTH` process environment variable, off by default) — matches web's posture exactly. Real `GetGoogleAuthURL`/`ExchangeGoogleCode` wiring (needs its own Google Cloud OAuth client + `ASWebAuthenticationSession`) is out of scope until a later phase.

## Testing

- **Swift Testing**, one `@Suite` per type, in `WellSpentTests/` (app target logic) and `Packages/WellSpentAPI/Tests/WellSpentAPITests/` (networking layer). Covers: JWT decode/expiry edge cases, Keychain round-trips (real Simulator Keychain — works fine under `xcodebuild test`, each test uses a unique service name to avoid cross-test interference), `AuthInterceptor` header injection and 401 handling (constructed `HTTPRequest`/`ResponseMessage` values directly, no network mocking needed), view model validation + error-code-to-message mapping, `SessionStore` state transitions.
- Deliberately **not** unit tested: SwiftUI view bodies (no assertion value without a UI-test harness) and thin one-line pass-throughs to generated RPC methods.
- **XCUITest** smoke flows in `WellSpentUITests/`: `LoginSmokeTests` (valid + wrong-password), `RegisterSmokeTests` (fresh timestamp-suffixed email — no seeded account needed), `LogoutSmokeTests` (log out, then relaunch *without* the reset flag to prove the Keychain token was actually cleared, not just in-memory state). Login/Logout tests need a seeded account: `export UITEST_EMAIL=... UITEST_PASSWORD=...` before running. All three need `WellSpent-backend` running locally.
- The app supports a `-uiTestResetSession` launch argument (checked in `WellSpentApp.init`) that clears the Keychain token before `SessionStore` restores a session — every UI test starts from a known logged-out state instead of inheriting whatever the Simulator's Keychain has from a previous run.
- Accessibility identifiers are set explicitly on every interactive element and screen-level container (not inferred from label text) — i18n will change label text later, identifiers won't.

## Version bump

No version-bump convention wired up yet (unlike `WellSpent-web`'s `NEXT_PUBLIC_APP_VERSION`) — `MARKETING_VERSION` in the Xcode project defaults to `1.0` and isn't surfaced in the UI. Add this once there's an actual UI surface to show it in (Phase 2+); bump `MARKETING_VERSION` in both build configurations following the same patch/minor/major convention as the other repos.

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

## Roadmap (not started)

See the approved implementation plan for the full phase breakdown (Phase 2: core budget loop — budgets/periods/people/income/categories/payment methods/transactions/expense plan; Phase 3: savings, invites, alerts; Phase 4: Plaid, transaction review, tiers). Each phase should update this file's Architecture/Testing sections as new patterns get established, the same way `WellSpent-web/CLAUDE.md` accumulated its "Component composition" and "Mobile + desktop support" sections over time.
