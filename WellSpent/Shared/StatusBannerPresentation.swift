import Foundation
import SwiftUI
import WellSpentREST

/// Display rules for the operator-authored status banner.
///
/// Mirrors web's `severity.ts` deliberately: both clients read the same rows
/// from the same endpoint, so a banner that reads as a warning in a browser
/// must not read as reassurance on a phone.
///
/// One asymmetry worth knowing about. Web's severity is a TypeScript string
/// union, which is compile-time only — an unrecognised value flows through and
/// lands on the `default` branch. The generated Swift enum is closed, so an
/// unrecognised value fails to decode the whole response and the banner simply
/// does not appear. That is bounded rather than fixed: `status_banner.severity`
/// carries a database CHECK constraint allowing exactly these three values, so
/// a fourth cannot exist without a migration and a contract change that ship
/// together. The `default` arms below still hold for `warning`.
nonisolated enum StatusBannerPresentation {
    /// Background and foreground are decided together rather than the view
    /// picking a background and hoping white text lands on it. Yellow with
    /// white text is close to unreadable, and the one banner that has to be
    /// legible is the one telling you something is wrong.
    static func background(for severity: StatusBannerSeverity) -> Color {
        switch severity {
        case .info: return .green
        case .critical: return .red
        // Covers .warning. Understating a severity is the worse failure of
        // the two, so nothing falls through to green.
        default: return .yellow
        }
    }

    static func foreground(for severity: StatusBannerSeverity) -> Color {
        switch severity {
        case .info, .critical: return .white
        default: return .black
        }
    }

    static func systemImage(for severity: StatusBannerSeverity) -> String {
        switch severity {
        case .info: return "checkmark.circle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    /// A critical banner can't be dismissed — one the user can swipe away
    /// isn't doing its job. Green and yellow are informational enough that
    /// pinning them would just be noise.
    static func isDismissible(_ severity: StatusBannerSeverity) -> Bool {
        severity != .critical
    }

    /// Picks the text for the reader's language, falling back to English.
    ///
    /// `message_es` is optional on the server: an operator posting mid-incident
    /// shouldn't be blocked on writing Spanish, and English text beats a blank
    /// bar.
    static func message(
        for banner: StatusBanner,
        languageCode: String = AppLanguageStore.currentLocale.identifier
    ) -> String {
        let spanish = banner.messageEs.trimmingCharacters(in: .whitespacesAndNewlines)
        if languageCode.hasPrefix("es"), !spanish.isEmpty {
            return banner.messageEs
        }
        return banner.messageEn
    }
}
