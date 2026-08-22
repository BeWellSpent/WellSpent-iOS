import SwiftUI

/// The "✕" that replaces a modal sheet's "Cancel" button.
///
/// It stays a `Label` rather than a bare `Image` so VoiceOver still announces
/// "Cancel" instead of an unlabelled glyph, and so the existing — already
/// translated — `Cancel` catalog entry keeps being used.
///
/// The accessibility identifier is what UI tests should target: looking the
/// button up by its label works only while the simulator runs in English, and
/// this repo has a locale-switching UI test.
struct SheetCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Cancel", systemImage: "xmark")
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("sheetCancelButton")
    }
}

/// Compact chrome shared by every modal sheet: an inline title one step below
/// the system size, and a `SheetCancelButton` in place of a "Cancel" button.
///
/// Both halves buy room, which is the whole point (issue #57). An inline
/// navigation title only gets whatever horizontal space the toolbar leaves it,
/// and a text "Cancel" costs far more of that than the glyph does — "Split
/// into installments" is the title that ran out of it. Dropping below the
/// system's 17pt and scaling down rather than truncating closes the rest of
/// the gap. Forcing `.inline` also reclaims the ~50pt of vertical space a
/// large title costs on the sheets that previously defaulted to one.
///
/// `title` is a `Text`, not a `LocalizedStringKey`, because the titles are not
/// all literals: a couple of sheets are titled after a category whose name is
/// already localized at runtime and must not be looked up a second time (those
/// pass `Text(verbatim:)`).
///
/// `onCancel` is optional for the one sheet whose leading button is not a
/// cancel — `BudgetSetupFlow` says "Finish Later" past its first step, which
/// is a statement a glyph can't make. Those callers supply their own
/// `.cancellationAction` item and take only the title treatment.
struct SheetChrome: ViewModifier {
    let title: Text
    let onCancel: (() -> Void)?

    /// One step down from the system's inline title (17pt semibold), keeping
    /// the semibold weight so the bar still reads as a title rather than as a
    /// caption.
    private static let titleFont: Font = .subheadline.weight(.semibold)

    /// Only engages once a title is too long for the space between the
    /// toolbar's buttons; the shrink is preferable to the ellipsis it replaces.
    private static let minimumScaleFactor: CGFloat = 0.75

    func body(content: Content) -> some View {
        content
            // Kept alongside the principal item: the principal item is how the
            // title is *drawn*, `navigationTitle` is what the title *is*.
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    title
                        .font(Self.titleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(Self.minimumScaleFactor)
                }
                if let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCancelButton(action: onCancel)
                    }
                }
            }
    }
}

extension View {
    /// Applies the standard sheet chrome. See `SheetChrome`.
    func sheetChrome(_ title: Text, onCancel: (() -> Void)? = nil) -> some View {
        modifier(SheetChrome(title: title, onCancel: onCancel))
    }
}
