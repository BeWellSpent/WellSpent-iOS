import Foundation

/// Single source of truth for the effective app locale outside SwiftUI view
/// context. `Text(_:LocalizedStringKey)` in view bodies reads `\.locale` from
/// the environment automatically (`WellSpentApp` sets that environment value
/// from this same cached key). Non-view code — `@Observable` view models and
/// the `*Label` enum helpers that return a plain `String` from a `switch` —
/// has no environment to read, so every `String(localized:)` call outside a
/// view body must pass **both** `currentBundle` and `currentLocale`. The
/// bundle is what selects the language; `locale:` alone only formats
/// interpolated values and silently returns English.
nonisolated enum AppLanguageStore {
    static let key = "appLanguage"

    static var currentLocale: Locale {
        locale(in: .standard)
    }

    /// Store passed in rather than read from a mutable global: tests need
    /// their own suite, and any view model calling `apply` writes this key,
    /// so a shared mutable pointer just moves the race rather than fixing it.
    static func locale(in defaults: UserDefaults) -> Locale {
        guard let code = defaults.string(forKey: key), !code.isEmpty else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: code)
    }

    /// The bundle is what selects the language. `String(localized:)`'s
    /// `locale:` argument only formats interpolated values — lookup always
    /// uses the main bundle's system language, so `locale:` alone returns
    /// English no matter what the user picked.
    static var currentBundle: Bundle {
        bundle(in: .standard)
    }

    static func bundle(in defaults: UserDefaults) -> Bundle {
        guard let code = defaults.string(forKey: key), !code.isEmpty else {
            return .main
        }
        let candidates = [code, Locale(identifier: code).language.languageCode?.identifier].compactMap { $0 }
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }

    /// Called after every successful `GetMe`/`UpdateMe` so the cached value
    /// (and therefore `.environment(\.locale:)` at the app root, via
    /// `@AppStorage` observing the same key) reflects the account's saved
    /// `language` immediately. Mirrors `ThemePreference`'s `@AppStorage`
    /// pattern, except language is server-persisted (`User.language`) rather
    /// than a device-only preference, so it's populated from the fetched
    /// `User` rather than a user-facing "system" option.
    static func apply(_ language: String, in defaults: UserDefaults = .standard) {
        guard !language.isEmpty else { return }
        defaults.set(language, forKey: key)
    }

    /// Called on logout so a different account logging in next doesn't
    /// briefly inherit the previous account's language before its own
    /// `GetMe` resolves.
    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
