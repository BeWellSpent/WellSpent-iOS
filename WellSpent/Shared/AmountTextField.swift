import SwiftUI

/// A money-amount `TextField` that filters to digits and at most one
/// decimal point as the user types, regardless of input source.
/// `.keyboardType(.decimalPad)` alone only restricts the on-screen keyboard
/// — it does nothing against a hardware keyboard (Simulator's default when
/// a Mac keyboard is attached) or paste, both of which can insert arbitrary
/// text. `MoneyInput.parseAmount` still does the real parse/validate at
/// submit time; this only stops obviously-invalid characters from landing
/// in the field at all. Used by every add/edit form that takes a money
/// amount — accessibility identifiers and layout modifiers (e.g.
/// `.multilineTextAlignment`) are applied by the caller, same as any other
/// `TextField`.
struct AmountTextField: View {
    let title: String
    @Binding var text: String

    init(_ title: String = "Amount", text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .onChange(of: text) { _, newValue in
                let sanitized = MoneyInput.sanitize(newValue)
                if sanitized != newValue {
                    text = sanitized
                }
            }
    }
}
