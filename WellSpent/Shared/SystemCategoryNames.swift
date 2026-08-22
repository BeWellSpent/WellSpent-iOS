import Foundation
import WellSpentAPI

/// Display names for the seeded system categories.
///
/// System category names are stored in the database in English and served as
/// such, so no string catalog could reach them — a catalog only knows
/// compile-time literals, and these are database rows. `Category.systemCategory`
/// gives each one a typed identity, which is what makes translating them
/// possible here (issue #49).
///
/// Mirrors web's `src/lib/categories/systemCategory.ts`. Keep the two in step:
/// a category reading "Groceries" on one client and "Supermercado" on the other
/// is the kind of divergence `docs/specs/02-architecture.md` warns about.
///
/// Accessibility identifiers deliberately keep using the raw `category.name`.
/// Building them from the translated name would make every UI test that looks
/// up `planCategoryRow_Groceries` fail whenever the simulator runs in Spanish,
/// for no benefit — an identifier is not read by anyone.
nonisolated enum SystemCategoryNames {
    /// The localized label for a category.
    ///
    /// A user-created category (`.unspecified`) is returned verbatim — those are
    /// the user's own words and are never translated.
    ///
    /// The fallback to `category.name` is load-bearing rather than defensive.
    /// The server always sends the English name, so a category seeded *after*
    /// this build shipped arrives carrying an enum case this binary has never
    /// seen and still reads as English instead of blank.
    static func displayName(_ category: Wellspent_V1_Category) -> String {
        displayName(systemCategory: category.systemCategory, fallback: category.name)
    }

    static func displayName(systemCategory: Wellspent_V1_SystemCategory, fallback: String) -> String {
        guard let key = localizedKey(for: systemCategory) else { return fallback }
        return String(localized: key, bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
    }

    /// `switch` with no `default`, deliberately: adding a case to
    /// `Wellspent_V1_SystemCategory` then fails to compile here rather than
    /// silently rendering that category in English forever.
    ///
    /// `UNRECOGNIZED` is the wire value for an enum number this build predates,
    /// which is the same situation as `.unspecified` from the reader's side.
    private static func localizedKey(for category: Wellspent_V1_SystemCategory) -> String.LocalizationValue? {
        switch category {
        case .unspecified, .UNRECOGNIZED: return nil
        case .entertainment: return "category.entertainment"
        case .insurance: return "category.insurance"
        case .loan: return "category.loan"
        case .wellness: return "category.wellness"
        case .services: return "category.services"
        case .subscription: return "category.subscription"
        case .rent: return "category.rent"
        case .travel: return "category.travel"
        case .eatingOut: return "category.eatingOut"
        case .groceries: return "category.groceries"
        case .baby: return "category.baby"
        case .pet: return "category.pet"
        case .misc: return "category.misc"
        case .house: return "category.house"
        case .gas: return "category.gas"
        case .auto: return "category.auto"
        case .savings: return "category.savings"
        case .shopping: return "category.shopping"
        case .family: return "category.family"
        case .income: return "category.income"
        case .payment: return "category.payment"
        case .transfer: return "category.transfer"
        case .transportation: return "category.transportation"
        case .utilities: return "category.utilities"
        case .debt: return "category.debt"
        }
    }

    /// Orders categories by the name actually on screen. The server sorts
    /// `ListCategories` by the English name, which stops being the reader's
    /// order once system categories are translated.
    static func sorted(_ categories: [Wellspent_V1_Category]) -> [Wellspent_V1_Category] {
        categories.sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
    }
}

extension Wellspent_V1_Category {
    /// The name to show the user. Translated for a system category, verbatim
    /// for one the user created.
    var displayName: String { SystemCategoryNames.displayName(self) }

    /// Whether this is the given system category.
    ///
    /// Replaces `isSystem && name == "Income"`, which stopped matching the
    /// moment the name was translated — silently, by simply never finding the
    /// category, so Income would have quietly stopped being excluded from
    /// spending totals.
    func isSystem(_ category: Wellspent_V1_SystemCategory) -> Bool {
        isSystem && systemCategory == category
    }
}
