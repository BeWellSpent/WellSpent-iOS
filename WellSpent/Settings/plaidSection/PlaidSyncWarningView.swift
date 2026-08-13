import SwiftUI
import WellSpentAPI

/// Warns that some connections on a shared budget will never sync.
///
/// Plaid sync is entitled per connection owner rather than per budget, so a
/// free-tier member of a paid budget can link a bank that the sync job skips
/// on every run. That was invisible on both clients — each only fetches the
/// caller's own connections, so a co-member's never appeared anywhere. One
/// went unsynced for over two weeks before anyone noticed.
struct PlaidSyncWarningView: View {
    let warnings: [Wellspent_V1_BudgetSyncWarning]

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(warnings, id: \.budgetProfileID) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Some accounts aren't syncing")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(message(for: warning))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("plaidSyncWarning_\(warning.budgetProfileID)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Built here rather than in the view body so the plural and self-vs-other
    /// wording stay one readable decision. `String(localized:locale:)` with an
    /// explicit locale, not the parameterless form, so it follows the
    /// account's chosen language rather than the device's.
    private func message(for warning: Wellspent_V1_BudgetSyncWarning) -> String {
        let locale = AppLanguageStore.currentLocale
        if warning.isCurrentUser {
            let format = String(
                localized: "You connected %lld bank(s) to %@, but your account isn't on a paid plan, so those transactions won't be imported. Upgrade to Pro to turn bank sync on.",
                locale: locale
            )
            return String(format: format, Int64(warning.connectionCount), warning.budgetName)
        }
        let format = String(
            localized: "%@ connected %lld bank(s) to %@, but their account isn't on a paid plan, so those transactions won't be imported. Bank sync is per person, so they'll need to upgrade.",
            locale: locale
        )
        return String(format: format, warning.memberName, Int64(warning.connectionCount), warning.budgetName)
    }
}

#Preview {
    PlaidSyncWarningView(warnings: [
        .with {
            $0.budgetProfileID = "profile-1"
            $0.budgetName = "Household"
            $0.memberName = "Alex"
            $0.connectionCount = 2
            $0.isCurrentUser = false
        },
        .with {
            $0.budgetProfileID = "profile-2"
            $0.budgetName = "Shared"
            $0.memberName = "Me"
            $0.connectionCount = 1
            $0.isCurrentUser = true
        },
    ])
    .padding()
}
