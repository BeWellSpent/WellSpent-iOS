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

#Preview {
    HStack {
        ColorDotView(hex: "#EF5350")
        ColorDotView(hex: "")
    }
}
