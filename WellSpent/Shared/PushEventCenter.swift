import Foundation

/// Decoded from a push payload's custom `alertType`/`budgetProfileId` keys
/// (siblings of `aps`, set by the backend on every notification send).
struct PushEvent: Sendable {
    let alertType: String
    let budgetProfileID: String
}

/// One-to-many broadcaster for incoming push notifications: unlike
/// `AppDelegate.onDeviceToken`'s single static closure, both the notification
/// bell and the transaction review badge need to independently observe every
/// push for the lifetime of `BudgetDetailView`, so each subscriber gets its
/// own `AsyncStream`.
final class PushEventCenter {
    static let shared = PushEventCenter()

    private var continuations: [UUID: AsyncStream<PushEvent>.Continuation] = [:]
    private let lock = NSLock()

    /// Not private — `.shared` is the one every subscriber/publisher in the
    /// app actually uses, but tests construct their own isolated instance.
    init() {}

    /// Call once per long-running subscriber `.task`; the stream ends and is
    /// removed automatically when that task is cancelled.
    func subscribe() -> AsyncStream<PushEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    func publish(_ event: PushEvent) {
        lock.lock()
        let subscribers = Array(continuations.values)
        lock.unlock()
        for continuation in subscribers {
            continuation.yield(event)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
