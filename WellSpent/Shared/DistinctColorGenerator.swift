import Foundation

/// Ports web's `categoriesPanel/colorUtils.ts` `generateDistinctColors`
/// exactly — golden-angle hue stepping from a random start hue gives evenly
/// spaced, visually distinct colors regardless of count.
nonisolated enum DistinctColorGenerator {
    static func generate(count: Int, startHue: Double = Double.random(in: 0..<360)) -> [String] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            hex(hue: (startHue + Double(i) * 137.508).truncatingRemainder(dividingBy: 360), saturation: 0.65, lightness: 0.50)
        }
    }

    private static func hex(hue: Double, saturation: Double, lightness: Double) -> String {
        let a = saturation * min(lightness, 1 - lightness)
        func component(_ n: Double) -> Int {
            let k = (n + hue / 30).truncatingRemainder(dividingBy: 12)
            let c = lightness - a * max(min(min(k - 3, 9 - k), 1), -1)
            return max(0, min(255, Int((255 * c).rounded())))
        }
        return String(format: "#%02X%02X%02X", component(0), component(8), component(4))
    }
}
