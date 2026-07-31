import SwiftUI

struct NotificationBellButton: View {
    let viewModel: NotificationBellViewModel?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                if let count = viewModel?.unreadCount, count > 0 {
                    Text("\(min(count, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .padding(4)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                        .offset(x: 9, y: -9)
                }
            }
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
