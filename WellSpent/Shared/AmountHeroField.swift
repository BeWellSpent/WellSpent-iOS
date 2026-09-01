import SwiftUI

/// Big, centered amount entry — the first row of every Add/Edit form that
/// takes a money amount (Variable transactions, Fixed expenses), replacing
/// the small labeled field that used to sit further down the form. Shared so
/// Add and Edit look identical; `autoFocus` is the only difference callers
/// set between them — on when adding, off when editing. Mirrors web's
/// `AmountHeroField.tsx`.
struct AmountHeroField: View {
    @Binding var text: String
    var autoFocus: Bool = false
    var disabled: Bool = false
    var accessibilityIdentifier: String = ""

    @FocusState private var isFocused: Bool

    var body: some View {
        AmountTextField("0.00", text: $text)
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .focused($isFocused)
            .disabled(disabled)
            .accessibilityIdentifier(accessibilityIdentifier)
            .onAppear { if autoFocus { isFocused = true } }
    }
}
