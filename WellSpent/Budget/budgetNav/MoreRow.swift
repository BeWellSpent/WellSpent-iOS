import SwiftUI
import WellSpentAPI

/// A white card of rows, the More sheet's groups. Rows add `MoreRowDivider` between them.
struct MoreRowGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .buttonStyle(.plain)
    }
}

/// The hairline between rows, starting after the icon tile.
struct MoreRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 60)
    }
}

/// An icon tile, a title (and optional subtitle), and a chevron.
struct MoreRow: View {
    let title: Text
    var subtitle: Text?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                title.foregroundStyle(.primary)
                if let subtitle {
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Your name, email and plan; opens Settings.
struct AccountRow: View {
    let user: Wellspent_V1_User?

    private var name: String {
        guard let user else { return "" }
        return [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var initials: String {
        guard let user else { return "" }
        return [user.firstName, user.lastName].compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: initials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if name.isEmpty {
                    Text("Settings").fontWeight(.semibold)
                } else {
                    Text(verbatim: name).fontWeight(.semibold)
                }
                if let user {
                    Text("\(user.email) · Settings")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let user {
                Text(PlanLabel.text(for: user.plan))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PlanLabel.tint(for: user.plan))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PlanLabel.tint(for: user.plan).opacity(0.14), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}
