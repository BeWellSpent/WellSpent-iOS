import SwiftUI

/// Bottom-anchored toast with an optional "Undo" action (issue #92) —
/// replaces `.confirmationDialog` for destructive/state-changing swipe
/// actions. Deliberately generic (message + optional undo + auto-dismiss),
/// not Variable-tab-specific, so Fixed/Payments can reuse it once their own
/// swipe-action passes land.
@MainActor
@Observable
final class ToastState {
    private(set) var message: String?
    private(set) var hasUndo = false
    private var undoAction: (() -> Void)?
    private var expireAction: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    /// Shows a toast. `onExpire` fires once, automatically, if the toast
    /// times out without `performUndo()` being called — this is what lets a
    /// swipe-delete stay reversible for a few seconds instead of deleting
    /// immediately.
    func show(_ message: String, onUndo: (() -> Void)? = nil, onExpire: (() -> Void)? = nil) {
        dismissTask?.cancel()
        self.message = message
        self.hasUndo = onUndo != nil
        self.undoAction = onUndo
        self.expireAction = onExpire
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.expireAction?()
            self?.clear()
        }
    }

    func performUndo() {
        dismissTask?.cancel()
        undoAction?()
        clear()
    }

    private func clear() {
        message = nil
        hasUndo = false
        undoAction = nil
        expireAction = nil
    }
}

private struct ToastView: View {
    let message: String
    let hasUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .foregroundStyle(.white)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hasUndo {
                Button("Undo", action: onUndo)
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("toastUndoButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("toastView")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Overlays `state`'s current toast at the bottom of this view.
    func toastOverlay(_ state: ToastState) -> some View {
        overlay(alignment: .bottom) {
            if let message = state.message {
                ToastView(message: message, hasUndo: state.hasUndo, onUndo: { state.performUndo() })
                    .padding(.bottom, 8)
                    .animation(.default, value: state.message)
            }
        }
    }
}
