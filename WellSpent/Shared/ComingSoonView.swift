import SwiftUI

/// Placeholder for a nav destination whose real content doesn't exist yet
/// (the Plan tab today; reusable later for other not-yet-built sections,
/// e.g. web's "Reports" placeholder).
struct ComingSoonView: View {
    let title: String
    let subtitle: String
    var systemImage: String = "hourglass"

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(subtitle))
    }
}

#Preview {
    ComingSoonView(title: "Expense Plan", subtitle: "Coming in a future phase.")
}
