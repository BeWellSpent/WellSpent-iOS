import SwiftUI
import WellSpentAPI

/// Display text/icon/tint for an `AccountPlan`. Unlike `alert_type`/
/// `threshold_scope`, `plan` is a real proto enum already, not a raw wire
/// string — this is just a display-layer helper, not a wire-format shim.
nonisolated enum PlanLabel {
    static func text(for plan: Wellspent_V1_AccountPlan) -> String {
        switch plan {
        case .unspecified, .free:
            return "Free"
        case .pro:
            return "Pro"
        case .lifetime:
            return "Lifetime"
        case .UNRECOGNIZED:
            return "Unknown"
        }
    }

    static func systemImage(for plan: Wellspent_V1_AccountPlan) -> String {
        switch plan {
        case .unspecified, .free:
            return "person"
        case .pro, .lifetime:
            return "crown.fill"
        case .UNRECOGNIZED:
            return "questionmark"
        }
    }

    /// Matches web's chip coloring (`warning`/`primary`/`disabled`).
    static func tint(for plan: Wellspent_V1_AccountPlan) -> Color {
        switch plan {
        case .unspecified, .free:
            return .secondary
        case .pro:
            return .blue
        case .lifetime:
            return .orange
        case .UNRECOGNIZED:
            return .secondary
        }
    }
}
