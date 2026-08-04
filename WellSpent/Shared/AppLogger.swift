import Foundation
import os

/// Central place for this app's logging subsystem — every `Logger` should
/// come from `AppLogger.logger(_:)` so Console.app can filter by a single
/// subsystem, with `category` naming the feature/component (e.g.
/// "FixedExpenses", "GoogleAuth"). Deliberately *not* a `print()`/`NSLog()`
/// wrapper: `os.Logger` (unified logging) persists to the system log and is
/// visible in Console.app regardless of how the app was launched — including
/// a standalone TestFlight/Home-screen launch with no debugger attached,
/// unlike `print()` (see the Google Sign-In debugging history in
/// `docs/features/google-auth.md` for why that distinction mattered live).
///
/// Deliberately *not* a `log(event:, context:)` wrapper mirroring web's
/// `src/lib/logger` — `os.Logger`'s actual value is that each interpolated
/// value in a format string is captured as its own typed, privacy-scoped
/// field (individually visible/filterable in Console.app), which only works
/// if call sites interpolate directly into the log call. Pre-flattening
/// identifiers into one `String` before it ever reaches `Logger` throws that
/// away. Call sites should hold their own category logger and interpolate
/// directly, e.g.:
/// ```swift
/// private static let logger = AppLogger.logger("FixedExpenses")
/// ...
/// Self.logger.error("template lookup failed transactionID=\(id, privacy: .public)")
/// ```
enum AppLogger {
    static func logger(_ category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.bewellspent.WellSpent", category: category)
    }
}
