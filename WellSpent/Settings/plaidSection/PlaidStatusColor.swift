import SwiftUI

/// Mirrors web's `statusColor.ts` — `status` is a raw wire string
/// (`active`/`disconnected`/`error`), not a proto enum.
nonisolated enum PlaidStatusColor {
    static func color(for status: String) -> Color {
        switch status {
        case "active": return .green
        case "error": return .red
        default: return .secondary
        }
    }
}
