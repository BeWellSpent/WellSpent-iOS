import Foundation
import Testing

/// Fails when a key in `Localizable.xcstrings` has no translation for a
/// supported language. Xcode auto-extracts new literals into the catalog with
/// English only and nothing warns, so untranslated strings had been shipping
/// unnoticed. Mirrors web's `translationKeys.test.ts`.
@Suite("LocalizationCatalog")
struct LocalizationCatalogTests {
    /// Read from the repo, not the test bundle — the bundle carries compiled
    /// `.strings`, which no longer distinguishes "translated" from "absent".
    static let catalogURL = URL(filePath: #filePath)
        .deletingLastPathComponent()   // WellSpentTests
        .deletingLastPathComponent()   // repo root
        .appending(path: "WellSpent/Localizable.xcstrings")

    static let requiredLanguages = ["es"]

    struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]

        struct Entry: Decodable {
            let localizations: [String: Localization]?
            /// Set on keys that are their own English value (Xcode omits the
            /// source-language entry for those) and on deliberately-skipped ones.
            let shouldTranslate: Bool?
        }

        struct Localization: Decodable {
            let stringUnit: StringUnit?
        }

        struct StringUnit: Decodable {
            let state: String
            let value: String
        }
    }

    static func loadCatalog() throws -> Catalog {
        let data = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    @Test("every key has a translated value in every supported language")
    func everyKeyIsTranslated() throws {
        let catalog = try Self.loadCatalog()

        var untranslated: [String: [String]] = [:]
        for language in Self.requiredLanguages {
            for (key, entry) in catalog.strings {
                if entry.shouldTranslate == false { continue }
                let unit = entry.localizations?[language]?.stringUnit
                guard let unit, unit.state == "translated", !unit.value.isEmpty else {
                    untranslated[language, default: []].append(key)
                    continue
                }
            }
        }

        let report = untranslated
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.sorted().map { "\"\($0)\"" }.joined(separator: ", "))" }
            .joined(separator: "\n")

        #expect(
            untranslated.isEmpty,
            """
            Keys missing a translation. Add them in Localizable.xcstrings \
            (Xcode extracts new literals with English only):
            \(report)
            """
        )
    }

    @Test("catalog is the expected shape")
    func catalogLoads() throws {
        let catalog = try Self.loadCatalog()
        #expect(catalog.sourceLanguage == "en")
        #expect(catalog.strings.count > 300)
    }
}
