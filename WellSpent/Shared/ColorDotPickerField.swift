import SwiftUI

/// One selectable option for `ColorDotPickerField`.
struct ColorDotOption<ID: Hashable>: Identifiable {
    let id: ID
    let name: String
    let hex: String
}

/// Replaces a native `Picker` for category/person/payment-method selection.
/// SwiftUI's `Picker` only renders a `Label`'s icon inside its expanded
/// options — the collapsed trailing value shows text only, so a native
/// Picker can never show the color dot for the *currently selected* item.
/// This field instead renders its own collapsed row (dot + name + chevron,
/// tappable) and presents a `.sheet` with a plain `List` of dot + name rows
/// for selection — `List` is the same rendering `AddPlanCategoryView` and
/// every list-row site already rely on, so the dot is guaranteed to show in
/// both the collapsed and expanded states.
///
/// `title`/`noneOption.label` are `LocalizedStringKey`, not `String` — every
/// call site passes a literal, so this resolves through the environment
/// locale the same way a plain `Text("...")` would. `option.name` stays
/// `String` since it's real user/server data (a category/person/payment-
/// method name), never translated.
struct ColorDotPickerField<ID: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: ID
    let options: [ColorDotOption<ID>]
    /// A "None"/"Unattributed"/"Select a person"-style option, shown above
    /// `options` in the sheet and as the collapsed placeholder when selected.
    let noneOption: (id: ID, label: LocalizedStringKey)?
    let accessibilityIdentifier: String

    @State private var isPresented = false

    init(
        title: LocalizedStringKey,
        selection: Binding<ID>,
        options: [ColorDotOption<ID>],
        noneOption: (id: ID, label: LocalizedStringKey)? = nil,
        accessibilityIdentifier: String
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.noneOption = noneOption
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private var selectedOption: ColorDotOption<ID>? {
        options.first { $0.id == selection }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let selectedOption {
                    ColorDotView(hex: selectedOption.hex, diameter: 10)
                    Text(selectedOption.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(noneOption?.label ?? "Select")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                List {
                    if let noneOption {
                        noneOptionRow(id: noneOption.id, label: noneOption.label)
                    }
                    ForEach(options) { option in
                        optionRow(id: option.id, name: option.name, hex: option.hex)
                    }
                }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// Kept separate from `optionRow` because its identifier must stay
    /// locale-independent — `optionRow`'s identifier is derived from a real
    /// (untranslated) name, but `noneOption.label` is itself translated, so
    /// baking it into the identifier would break under a non-English locale.
    @ViewBuilder
    private func noneOptionRow(id: ID, label: LocalizedStringKey) -> some View {
        Button {
            selection = id
            isPresented = false
        } label: {
            HStack {
                ColorDotView(hex: "", diameter: 10)
                Text(label)
                Spacer()
                if selection == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("\(accessibilityIdentifier)_option_none")
    }

    @ViewBuilder
    private func optionRow(id: ID, name: String, hex: String) -> some View {
        Button {
            selection = id
            isPresented = false
        } label: {
            HStack {
                ColorDotView(hex: hex, diameter: 10)
                Text(name)
                Spacer()
                if selection == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("\(accessibilityIdentifier)_option_\(name)")
    }
}

#Preview {
    @Previewable @State var categoryID: Int32 = 1
    Form {
        ColorDotPickerField(
            title: "Category",
            selection: $categoryID,
            options: [
                ColorDotOption(id: Int32(1), name: "Groceries", hex: "#EF5350"),
                ColorDotOption(id: Int32(2), name: "Dining", hex: "#42A5F5"),
            ],
            noneOption: (id: Int32(0), label: "None"),
            accessibilityIdentifier: "previewCategoryPicker"
        )
    }
}
