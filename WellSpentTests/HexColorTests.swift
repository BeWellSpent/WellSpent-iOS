import Testing
@testable import WellSpent

@Suite("HexColor")
struct HexColorTests {
    @Test("rgb parses a valid 6-digit hex string with a leading #")
    func rgbParsesValidHex() {
        let rgb = HexColor.rgb(from: "#FF0000")
        #expect(rgb.red == 1.0)
        #expect(rgb.green == 0.0)
        #expect(rgb.blue == 0.0)
    }

    @Test("rgb parses without a leading #")
    func rgbParsesWithoutHash() {
        let rgb = HexColor.rgb(from: "00FF00")
        #expect(rgb.red == 0.0)
        #expect(rgb.green == 1.0)
        #expect(rgb.blue == 0.0)
    }

    @Test("rgb returns black for invalid input")
    func rgbFallsBackForInvalidInput() {
        let rgb = HexColor.rgb(from: "not-a-color")
        #expect(rgb == (0, 0, 0))
    }

    @Test("hexString round-trips a known RGB value")
    func hexStringRoundTrips() {
        #expect(HexColor.hexString(red: 1.0, green: 0.0, blue: 0.0) == "#FF0000")
        #expect(HexColor.hexString(red: 0.0, green: 1.0, blue: 0.0) == "#00FF00")
        #expect(HexColor.hexString(red: 0.0, green: 0.0, blue: 1.0) == "#0000FF")
    }

    @Test("hexString clamps out-of-range components")
    func hexStringClampsOutOfRange() {
        #expect(HexColor.hexString(red: 2.0, green: -1.0, blue: 0.5) == "#FF0080")
    }
}
