import Foundation
import Testing
@testable import WellSpent

@Suite("AppLanguageStore", .serialized)
struct AppLanguageStoreTests {
    /// Every test uses a private store: view-model suites call
    /// `AppLanguageStore.apply` on `.standard` in parallel, which is what made
    /// this suite flaky even when marked `.serialized`.
    private let defaults = UserDefaults(suiteName: "AppLanguageStoreTests-\(UUID().uuidString)")!

    /// Private store, so view-model tests calling `apply` on `.standard` in
    /// parallel can't clobber the bundle-lookup assertions below.
    private func isolatedDefaults(_ code: String?) -> UserDefaults {
        let store = UserDefaults(suiteName: "AppLanguageStoreBundle-\(UUID().uuidString)")!
        if let code {
            store.set(code, forKey: AppLanguageStore.key)
        }
        return store
    }

    @Test("currentLocale falls back to device locale when nothing cached")
    func fallsBackWhenUnset() {
        #expect(defaults.string(forKey: AppLanguageStore.key) == nil)
        #expect(AppLanguageStore.locale(in: defaults) == .autoupdatingCurrent)
    }

    @Test("apply caches the language and currentLocale reflects it immediately")
    func applyUpdatesCurrentLocale() {
        AppLanguageStore.apply("es", in: defaults)
        #expect(AppLanguageStore.locale(in: defaults).identifier == Locale(identifier: "es").identifier)
    }

    @Test("apply ignores an empty language")
    func applyIgnoresEmpty() {
        AppLanguageStore.apply("es", in: defaults)
        AppLanguageStore.apply("", in: defaults)
        #expect(AppLanguageStore.locale(in: defaults).identifier == Locale(identifier: "es").identifier)
    }

    @Test("clear removes the cached language")
    func clearResets() {
        AppLanguageStore.apply("es", in: defaults)
        AppLanguageStore.clear(in: defaults)
        #expect(AppLanguageStore.locale(in: defaults) == .autoupdatingCurrent)
    }

    // MARK: - Bundle lookup

    @Test("locale: alone does not translate — the reason the *Label helpers shipped English")
    func localeAloneDoesNotTranslate() {
        #expect(String(localized: "Log In", locale: Locale(identifier: "es")) == "Log In")
    }

    @Test("the resolved bundle is what translates")
    func resolvedBundleTranslates() {
        let bundle = AppLanguageStore.bundle(in: isolatedDefaults("es"))
        #expect(String(localized: "Log In", bundle: bundle, locale: Locale(identifier: "es")) == "Iniciar sesión")
        // The strings the tester reported as untranslated.
        #expect(String(localized: "All transactions", bundle: bundle, locale: Locale(identifier: "es")) == "Todas las transacciones")
        #expect(String(localized: "Transactions", bundle: bundle, locale: Locale(identifier: "es")) == "Transacciones")
    }

    @Test("falls back to the main bundle for an unknown language")
    func unknownLanguageFallsBack() {
        #expect(AppLanguageStore.bundle(in: isolatedDefaults("qq")) == Bundle.main)
        #expect(AppLanguageStore.bundle(in: isolatedDefaults(nil)) == Bundle.main)
    }

    @Test("regional code resolves to its base language")
    func regionalCodeResolves() {
        let bundle = AppLanguageStore.bundle(in: isolatedDefaults("es-419"))
        #expect(String(localized: "Log In", bundle: bundle, locale: Locale(identifier: "es")) == "Iniciar sesión")
    }
}
