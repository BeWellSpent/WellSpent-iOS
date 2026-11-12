import SwiftUI

/// Building blocks for the sign-up, log-in and budget-setup screens, matching
/// Home's cards (`HomeCard`, `HomeSectionHeader`): a label above each field,
/// one filled primary action pinned to the bottom, tinted secondary actions.

/// A form field with its label above it, in the bordered box the design uses.
struct LabeledFieldBox<Field: View>: View {
    let label: Text
    var footnote: Text?
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            label
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            field
                .font(.body)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator)))
            if let footnote {
                footnote
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The screen's one filled, full-width action.
struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.accentColor.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// A full-width action that adds to a list ("Add person"): accent text on a light accent fill.
struct TintedActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

/// An outlined full-width button on the card colour (Google sign-in, Resend).
struct OutlinedActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// The large heading and one-line explanation that open each screen, in the
/// content rather than the navigation bar, where long titles used to get cut.
struct OnboardingHeading: View {
    let title: Text
    let subtitle: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// A one-line inline error in the red tint the Home cards use for "over plan".
struct InlineErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    /// Pins `bar` to the bottom above the home indicator, with a hairline above it.
    func pinnedActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                bar()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .top) { Divider() }
        }
    }
}
