import Foundation
import WellSpentAPI

/// Rules about inviting someone to a budget, shared by the setup wizard and
/// the Invites panel.
///
/// Mirrors web's `modals/addPeople/pendingPerson.ts` deliberately: which roles
/// can be handed out, and what counts as a plausible address, are answers that
/// must not differ between a phone and a browser.
nonisolated enum InviteEmail {
    /// Roles an invite can grant.
    ///
    /// Admin is deliberately absent, matching `InvitesListView` and web's
    /// invite panel: an admin can remove the person who invited them, which is
    /// not a decision to hand over from a picker in a setup wizard. It can
    /// still be granted afterwards from the People panel.
    static let invitableRoles: [Wellspent_V1_BudgetRole] = [.collaborator, .viewer]

    /// Deliberately permissive. The authoritative check is the server's; this
    /// only exists to stop an obvious typo becoming an invitation nobody
    /// receives, and a stricter pattern would reject addresses the backend
    /// accepts.
    static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" ") else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex else { return false }
        return domain.index(after: dot) < domain.endIndex
    }

    /// What each role actually permits, in the reader's own terms — the point
    /// of showing a role picker at all is that nobody guesses what "Viewer"
    /// costs them.
    static func roleDescription(for role: Wellspent_V1_BudgetRole) -> String {
        let locale = AppLanguageStore.currentLocale
        let bundle = AppLanguageStore.currentBundle
        switch role {
        case .viewer:
            return String(localized: "See the whole budget without changing anything.",
                          bundle: bundle, locale: locale)
        default:
            return String(localized: "Add and edit transactions, income and savings — but not manage people.",
                          bundle: bundle, locale: locale)
        }
    }
}
