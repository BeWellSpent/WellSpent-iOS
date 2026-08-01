import SwiftUI

/// Swatch-grid color picker — mirrors web's `ColorPicker.tsx`: tappable
/// circles for `PresetColors.all`, plus a native custom-color option (the
/// system `ColorPicker` swatch/well is iOS's equivalent of web's hidden
/// `<input type="color">`). Replaces the previous plain `Picker` showing raw
/// hex strings as text, which is what "colors show as a hash" meant.
struct PresetColorPickerView: View {
    @Binding var hex: String

    private var isCustomSelected: Bool {
        !hex.isEmpty && !PresetColors.all.contains(hex)
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { isCustomSelected ? Color(hexString: hex) : .gray },
            set: { hex = $0.toHexString() }
        )
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                noneSwatch

                ForEach(PresetColors.all, id: \.self) { presetHex in
                    swatch(hex: presetHex)
                }

                ColorPicker("Custom color", selection: customColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityIdentifier("customColorPicker")
            }
            .padding(.vertical, 4)
        }
    }

    private var noneSwatch: some View {
        Button {
            hex = ""
        } label: {
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3]))
                .frame(width: 28, height: 28)
                .overlay {
                    if hex.isEmpty {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("colorSwatch_none")
    }

    private func swatch(hex presetHex: String) -> some View {
        Button {
            hex = presetHex
        } label: {
            Circle()
                .fill(Color(hexString: presetHex))
                .frame(width: 28, height: 28)
                .overlay {
                    if hex == presetHex {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("colorSwatch_\(presetHex)")
    }
}

#Preview {
    PresetColorPickerView(hex: .constant(PresetColors.all[2]))
        .padding()
}
