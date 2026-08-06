import SwiftUI

struct NotificationBellButton: View {
    let viewModel: NotificationBellViewModel?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // Fixed frame reserves real layout room for the badge instead of
            // relying on it overflowing past the icon's own bounds via
            // offset — otherwise a tightly packed toolbar (e.g. this bell
            // alongside two other icons on the Transactions tab) can clip it.
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                if let count = viewModel?.unreadCount, count > 0 {
                    Text("\(min(count, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        // Capsule, not Circle — Circle clips to an ellipse
                        // matching the frame's own aspect ratio, so a 2-digit
                        // count stretches into an odd oval instead of a pill.
                        .background(Capsule().fill(Color.red))
                        .foregroundStyle(.white)
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: 32, height: 32)
        }
        .accessibilityIdentifier("notificationBellButton")
        .popover(isPresented: $isPresented) {
            NotificationInboxView(viewModel: viewModel)
                .presentationCompactAdaptation(.popover)
        }
    }
}

#Preview {
    NotificationBellButton(viewModel: nil)
}
