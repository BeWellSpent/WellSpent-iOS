import Foundation
import WellSpentAPI

/// Which matches the Review tab shows.
struct ReviewFilter: Equatable {
    enum Strength: Equatable { case any, strong, possible }

    /// nil = every period.
    var periodID: String?
    var strength: Strength = .any
    var bankOnly = false

    /// The score at and above which a match reads as strong.
    static let strongScore: Double = 90

    var isActive: Bool { periodID != nil || strength != .any || bankOnly }

    func includes(_ group: ReviewGroup) -> Bool {
        let score = group.reviews.map(\.matchScore).max() ?? 0
        switch strength {
        case .any: break
        case .strong: if score < Self.strongScore { return false }
        case .possible: if score >= Self.strongScore { return false }
        }
        if bankOnly, !group.reviews.allSatisfy(\.transactionImported) { return false }
        return true
    }
}

/// One period's pending matches, the unit the Review tab collapses.
struct ReviewPeriodSection: Identifiable {
    let periodID: String
    /// nil when the period isn't in the loaded list (shouldn't happen; shown last as "Other").
    let period: Wellspent_V1_BudgetPeriod?
    let isCurrent: Bool
    let groups: [ReviewGroup]
    var id: String { periodID }
}

/// Splits pending matches by period, newest period first, after filtering.
nonisolated enum ReviewPeriodSections {
    static func build(
        groups: [ReviewGroup],
        periods: [Wellspent_V1_BudgetPeriod],
        currentPeriodID: String?,
        filter: ReviewFilter
    ) -> [ReviewPeriodSection] {
        let byID = Dictionary(periods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var order: [String] = []
        var grouped: [String: [ReviewGroup]] = [:]
        for group in groups where filter.includes(group) {
            let periodID = group.reviews.first?.budgetPeriodID ?? ""
            if let wanted = filter.periodID, wanted != periodID { continue }
            if grouped[periodID] == nil { order.append(periodID) }
            grouped[periodID, default: []].append(group)
        }
        return order
            .map { id in
                ReviewPeriodSection(periodID: id, period: byID[id], isCurrent: id == currentPeriodID, groups: grouped[id] ?? [])
            }
            .sorted { lhs, rhs in
                switch (lhs.period, rhs.period) {
                case let (l?, r?): return l.startDate.seconds > r.startDate.seconds
                case (_?, nil): return true
                default: return false
                }
            }
    }

    /// Periods that have pending matches, newest first: the period filter's choices.
    static func periodsWithMatches(groups: [ReviewGroup], periods: [Wellspent_V1_BudgetPeriod]) -> [Wellspent_V1_BudgetPeriod] {
        let ids = Set(groups.compactMap { $0.reviews.first?.budgetPeriodID })
        return periods.filter { ids.contains($0.id) }.sorted { $0.startDate.seconds > $1.startDate.seconds }
    }
}

/// The line under a matched transaction's name: "Bank · Checking · Nov 2".
nonisolated enum ReviewLineDetail {
    static func text(for review: Wellspent_V1_TransactionReview, localeIdentifier: String) -> String {
        let locale = AppLanguageStore.currentLocale
        let source = review.transactionImported
            ? String(localized: "Bank", bundle: AppLanguageStore.currentBundle, locale: locale)
            : String(localized: "Typed in", bundle: AppLanguageStore.currentBundle, locale: locale)
        var parts = [source]
        if !review.transactionPaymentMethodName.isEmpty { parts.append(review.transactionPaymentMethodName) }
        if review.hasTransactionDate {
            let style = Date.FormatStyle(locale: Locale(identifier: localeIdentifier)).month(.abbreviated).day()
            parts.append(review.transactionDate.dateOnly.formatted(style))
        }
        return parts.joined(separator: " · ")
    }
}
