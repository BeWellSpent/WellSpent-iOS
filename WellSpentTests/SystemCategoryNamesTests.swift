import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("SystemCategoryNames")
struct SystemCategoryNamesTests {
    private func category(
        _ systemCategory: Wellspent_V1_SystemCategory,
        name: String,
        isSystem: Bool = true
    ) -> Wellspent_V1_Category {
        .with {
            $0.id = 1
            $0.name = name
            $0.isSystem = isSystem
            $0.systemCategory = systemCategory
        }
    }

    // The whole reason `name` stays English on the wire. A category seeded
    // after this build shipped arrives carrying an enum number this binary has
    // never seen; it has to read as English, not as blank or a raw key.
    @Test("An unrecognised system category falls back to the server's English name")
    func unrecognisedFallsBackToName() {
        let future = category(.UNRECOGNIZED(99), name: "Childcare")
        #expect(SystemCategoryNames.displayName(future) == "Childcare")
    }

    @Test("A user-created category is returned verbatim")
    func userCategoryUnchanged() {
        let mine = category(.unspecified, name: "Bouldering gym", isSystem: false)
        #expect(SystemCategoryNames.displayName(mine) == "Bouldering gym")
    }

    // Every case must resolve to a catalog entry. A missing entry returns the
    // key itself, so assert the result differs from both the key and the
    // fallback — otherwise a forgotten translation looks like a pass.
    @Test("Every system category resolves to a real catalog string")
    func everyCaseHasAString() {
        let all = Wellspent_V1_SystemCategory.allCases.filter { $0 != .unspecified }
        #expect(all.count == 25)
        for value in all {
            let name = SystemCategoryNames.displayName(systemCategory: value, fallback: "FALLBACK")
            #expect(name != "FALLBACK", "\(value) has no catalog entry — it fell back to the English name")
            #expect(!name.hasPrefix("category."), "\(value) rendered its raw key")
            #expect(!name.isEmpty)
        }
    }

    // A user could name their own category "Income". Before this change, that
    // category would have been excluded from every spending total.
    @Test("isSystem(_:) matches on the enum, not on the name")
    func isSystemMatchesEnumNotName() {
        // Already translated — the check must still hold.
        #expect(category(.income, name: "Ingresos").isSystem(.income))
        #expect(!category(.income, name: "Income").isSystem(.savings))
        // A user category that happens to share the display name.
        let impostor = category(.unspecified, name: "Income", isSystem: false)
        #expect(!impostor.isSystem(.income))
    }

    // A system category flag without the matching enum value shouldn't match
    // either: both halves have to agree.
    @Test("isSystem(_:) requires both the flag and the enum value")
    func isSystemRequiresBoth() {
        #expect(!category(.unspecified, name: "Income").isSystem(.income))
    }

    @Test("sorted orders by the displayed name")
    func sortedUsesDisplayName() {
        let auto = category(.auto, name: "Auto")
        let savings = category(.savings, name: "Savings")
        let names = SystemCategoryNames.sorted([savings, auto]).map(\.displayName)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
}
