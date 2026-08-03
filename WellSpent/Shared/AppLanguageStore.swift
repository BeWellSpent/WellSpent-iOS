import Foundation

/// Single source of truth for the effective app locale outside SwiftUI view
/// context. `Text(_:LocalizedStringKey)` in view bodies reads `\.locale` from
/// the environment automatically (`WellSpentApp` sets that environment value
/// from this same cached key). Non-view code — `@Observable` view models and
/// the `*Label` enum helpers that return a plain `String` from a `switch` —
/// has no environment to read, so every `String(localized:)` call made
/// outside a view body must pass `AppLanguageStore.currentLocale` explicitly,
/// or it silently falls back to the device's system locale, which can differ
/// from the language the user actually chose in Settings.
nonisolated enum AppLanguageStore {
    static let key = "appLanguage"

    static var currentLocale: Locale {
        guard let code = UserDefaults.standard.string(forKey: key), !code.isEmpty else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: code)
    }

    /// Called after every successful `GetMe`/`UpdateMe` so the cached value
    /// (and therefore `.environment(\.locale:)` at the app root, via
    /// `@AppStorage` observing the same key) reflects the account's saved
    /// `language` immediately. Mirrors `ThemePreference`'s `@AppStorage`
    /// pattern, except language is server-persisted (`User.language`) rather
    /// than a device-only preference, so it's populated from the fetched
    /// `User` rather than a user-facing "system" option.
    static func apply(_ language: String) {
        guard !language.isEmpty else { return }
        UserDefaults.standard.set(language, forKey: key)
    }

    /// Called on logout so a different account logging in next doesn't
    /// briefly inherit the previous account's language before its own
    /// `GetMe` resolves.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
