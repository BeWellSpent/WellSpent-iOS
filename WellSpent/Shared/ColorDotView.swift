import SwiftUI

/// Small circular swatch for list rows — mirrors web's `ColorDot.tsx`.
/// Shown for people, categories, and payment methods.
struct ColorDotView: View {
    let hex: String
    var diameter: CGFloat = 12

    var body: some View {
        Circle()
            .fill(hex.isEmpty ? Color.clear : Color(hexString: hex))
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle().strokeBorder(hex.isEmpty ? Color.secondary.opacity(0.5) : Color.clear, lineWidth: 1)
            )
    }
}

/// A `Picker`/`Menu` option combining a color dot + label — the same visual
/// pairing `ColorDotView` provides for list rows, packaged for use inside a
/// `ForEach` building `Picker` options (category/person/payment-method
/// selection menus throughout the app).
struct ColorDotLabel: View {
    let title: String
    let hex: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            ColorDotView(hex: hex, diameter: 10)
        }
    }
}

#Preview {
    HStack {
        ColorDotView(hex: "#EF5350")
        ColorDotView(hex: "")
    }
}
