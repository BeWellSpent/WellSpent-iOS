import Foundation
import Testing
@testable import WellSpent

@Suite("AppLanguageStore", .serialized)
struct AppLanguageStoreTests {
    init() {
        AppLanguageStore.clear()
    }

    @Test("currentLocale falls back to device locale when nothing cached")
    func fallsBackWhenUnset() {
        #expect(UserDefaults.standard.string(forKey: AppLanguageStore.key) == nil)
        #expect(AppLanguageStore.currentLocale == .autoupdatingCurrent)
    }

    @Test("apply caches the language and currentLocale reflects it immediately")
    func applyUpdatesCurrentLocale() {
        AppLanguageStore.apply("es")
        #expect(AppLanguageStore.currentLocale.identifier == Locale(identifier: "es").identifier)
    }

    @Test("apply ignores an empty language")
    func applyIgnoresEmpty() {
        AppLanguageStore.apply("es")
        AppLanguageStore.apply("")
        #expect(AppLanguageStore.currentLocale.identifier == Locale(identifier: "es").identifier)
    }

    @Test("clear removes the cached language")
    func clearResets() {
        AppLanguageStore.apply("es")
        AppLanguageStore.clear()
        #expect(AppLanguageStore.currentLocale == .autoupdatingCurrent)
    }
}
