import Foundation
import SwiftUI
import WellSpentAPI

/// Display rules for the operator-authored status banner.
///
/// Mirrors web's `severity.ts` deliberately: both clients read the same rows
/// from the same RPC, so a banner that reads as a warning in a browser must not
/// read as reassurance on a phone.
nonisolated enum StatusBannerPresentation {
    /// Background and foreground are decided together rather than the view
    /// picking a background and hoping white text lands on it. Yellow with
    /// white text is close to unreadable, and the one banner that has to be
    /// legible is the one telling you something is wrong.
    static func background(for severity: Wellspent_V1_StatusBannerSeverity) -> Color {
        switch severity {
        case .info: return .green
        case .critical: return .red
        // Includes .unspecified, .warning and anything a future server sends
        // that this build doesn't know. Understating an unknown severity is
        // the worse failure, so it never falls through to green.
        default: return .yellow
        }
    }

    static func foreground(for severity: Wellspent_V1_StatusBannerSeverity) -> Color {
        switch severity {
        case .info, .critical: return .white
        default: return .black
        }
    }

    static func systemImage(for severity: Wellspent_V1_StatusBannerSeverity) -> String {
        switch severity {
        case .info: return "checkmark.circle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    /// A critical banner can't be dismissed — one the user can swipe away
    /// isn't doing its job. Green and yellow are informational enough that
    /// pinning them would just be noise.
    static func isDismissible(_ severity: Wellspent_V1_StatusBannerSeverity) -> Bool {
        severity != .critical
    }

    /// Picks the text for the reader's language, falling back to English.
    ///
    /// `message_es` is optional on the server: an operator posting mid-incident
    /// shouldn't be blocked on writing Spanish, and English text beats a blank
    /// bar.
    static func message(
        for banner: Wellspent_V1_StatusBanner,
        languageCode: String = AppLanguageStore.currentLocale.identifier
    ) -> String {
        let spanish = banner.messageEs.trimmingCharacters(in: .whitespacesAndNewlines)
        if languageCode.hasPrefix("es"), !spanish.isEmpty {
            return banner.messageEs
        }
        return banner.messageEn
    }
}
