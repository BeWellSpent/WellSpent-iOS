import SwiftUI

/// Mirrors web's `ThemeMode` (`'light' | 'dark' | 'system'`, persisted to
/// `localStorage['theme-mode']` via MUI's `CssVarsProvider`). `colorScheme`
/// is `nil` for `.system` so `.preferredColorScheme(nil)` defers to the OS.
nonisolated enum ThemePreference: String, CaseIterable {
    case light
    case dark
    case system

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var systemImage: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .system: "circle.lefthalf.filled"
        }
    }
}
