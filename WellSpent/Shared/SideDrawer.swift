import SwiftUI

/// A left-edge navigation drawer: slides in over the whole screen, dims what
/// is behind it, and closes by tapping the dimmed area or swiping back left.
/// It can also be pulled open from the left edge.
///
/// SwiftUI has no drawer of its own, so this is the usual composition — a
/// `ZStack` whose panel is offset by its own width when closed — with the two
/// details that are easy to get wrong done properly:
///
/// - **The drag is interactive, not a toggle.** `dragTranslation` moves the
///   panel and the scrim's opacity together while the finger is down, so the
///   gesture tracks rather than snapping at the end. Release uses the
///   *predicted* end translation, so a fast flick opens even if the finger
///   never travelled far.
/// - **Only horizontal intent counts.** A drag that is mostly vertical is
///   ignored, or scrolling the drawer's own list would drag the drawer
///   sideways at the same time.
///
/// The edge-grab strip only exists while closed, and it is safe here because
/// none of the four tab destinations push anything — there is no interactive
/// back gesture for it to compete with. **If a tab ever gains a
/// `NavigationLink`, this needs revisiting**: the system's swipe-from-left to
/// pop would land on this strip first.
struct SideDrawer<DrawerContent: View, Content: View>: View {
    @Binding private var isOpen: Bool
    private let drawer: DrawerContent
    private let content: Content

    @State private var dragTranslation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wide enough for a nav label, never so wide the screen behind it
    /// disappears — the sliver still showing is what says "a layer over your
    /// screen" rather than "a different screen".
    private let maxDrawerWidth: CGFloat = 320
    private let edgeGrabWidth: CGFloat = 24
    private let scrimOpacity: CGFloat = 0.35

    init(
        isOpen: Binding<Bool>,
        @ViewBuilder drawer: () -> DrawerContent,
        @ViewBuilder content: () -> Content
    ) {
        self._isOpen = isOpen
        self.drawer = drawer()
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let width = min(maxDrawerWidth, proxy.size.width * 0.85)
            let offset = currentOffset(width: width)
            // 0 fully closed .. 1 fully open. Drives the scrim so it fades in
            // step with the panel instead of popping.
            let progress = width == 0 ? 0 : 1 - (-offset / width)

            ZStack(alignment: .leading) {
                content

                Color.black
                    .opacity(scrimOpacity * progress)
                    .ignoresSafeArea()
                    // Untappable when shut, or it would eat every tap on the
                    // screen behind it.
                    .allowsHitTesting(progress > 0.01)
                    .onTapGesture { setOpen(false) }

                drawer
                    .frame(width: width)
                    // Background full-bleeds under the status bar and the tab
                    // bar; the content itself stays inside the safe area.
                    .background { Color(.systemBackground).ignoresSafeArea() }
                    .shadow(color: .black.opacity(0.2 * progress), radius: 8)
                    .offset(x: offset)
                    .gesture(dragGesture(width: width))
                    // Hidden from VoiceOver while shut so it cannot be swiped
                    // into off screen.
                    .accessibilityHidden(progress < 0.99)
            }
            .overlay(alignment: .leading) {
                if !isOpen {
                    Color.clear
                        .frame(width: edgeGrabWidth)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(width: width))
                }
            }
        }
    }

    private func currentOffset(width: CGFloat) -> CGFloat {
        let base = isOpen ? 0 : -width
        return min(0, max(-width, base + dragTranslation))
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    setOpen(isOpen)
                    return
                }
                // Predicted, not actual: a fast flick should complete even
                // though the finger stopped short of the threshold.
                let projected = value.predictedEndTranslation.width
                setOpen(isOpen ? projected > -width / 3 : projected > width / 3)
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            isOpen = open
            dragTranslation = 0
        }
    }
}

#Preview {
    @Previewable @State var isOpen = true
    return SideDrawer(isOpen: $isOpen) {
        List {
            Section("Period") {
                Text(verbatim: "August 2026")
                Text(verbatim: "July 2026")
            }
            Section {
                Text(verbatim: "Manage budget")
                Text(verbatim: "Settings")
            }
        }
    } content: {
        VStack {
            Text(verbatim: "Screen behind the drawer")
            Button("Toggle") { isOpen.toggle() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
    }
}
