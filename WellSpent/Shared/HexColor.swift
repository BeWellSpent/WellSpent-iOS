import SwiftUI

/// Hex-string ↔ RGB conversion — needed now that colors are actually
/// rendered as swatches (`ColorDotView`/`PresetColorPickerView`), not just
/// carried as opaque picker-selection state (the earlier "no `Color(hex:)`
/// parser needed" simplification predates that requirement).
nonisolated enum HexColor {
    static func rgb(from hex: String) -> (red: Double, green: Double, blue: Double) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
            return (0, 0, 0)
        }
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        return (red, green, blue)
    }

    static func hexString(red: Double, green: Double, blue: Double) -> String {
        func clamp(_ v: Double) -> Int {
            max(0, min(255, Int((v * 255).rounded())))
        }
        return String(format: "#%02X%02X%02X", clamp(red), clamp(green), clamp(blue))
    }
}

extension Color {
    init(hexString: String) {
        let rgb = HexColor.rgb(from: hexString)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Bridges through `UIColor` to read back sRGB components — used only
    /// for the native custom-color picker's result, not for preset swatches
    /// (which already carry their own known hex value).
    func toHexString() -> String {
        let components = UIColor(self).cgColor.components ?? [0, 0, 0]
        guard components.count >= 3 else { return "#000000" }
        return HexColor.hexString(red: components[0], green: components[1], blue: components[2])
    }
}
