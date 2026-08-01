import SwiftUI
import Testing
@testable import WellSpent

@Suite("ThemePreference")
struct ThemePreferenceTests {
    @Test("colorScheme maps light/dark to concrete schemes and system to nil")
    func colorSchemeMapping() {
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
        #expect(ThemePreference.system.colorScheme == nil)
    }

    @Test("rawValue round-trips for every case")
    func rawValueRoundTrips() {
        for mode in ThemePreference.allCases {
            #expect(ThemePreference(rawValue: mode.rawValue) == mode)
        }
    }
}
