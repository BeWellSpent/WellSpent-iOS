import Foundation
import SwiftUI
import Testing
import WellSpentREST
@testable import WellSpent

@Suite("StatusBannerPresentation")
struct StatusBannerPresentationTests {
    private func banner(
        messageEn: String = "Bank syncing is delayed.",
        messageEs: String = "La sincronización bancaria está retrasada."
    ) -> StatusBanner {
        StatusBanner(
            id: "b1",
            severity: .warning,
            messageEn: messageEn,
            messageEs: messageEs,
            startsAt: .now,
            endsAt: .now.addingTimeInterval(3600),
            createdAt: .now
        )
    }

    @Test("The three severities map to green, yellow and red")
    func backgroundPerSeverity() {
        #expect(StatusBannerPresentation.background(for: .info) == .green)
        #expect(StatusBannerPresentation.background(for: .warning) == .yellow)
        #expect(StatusBannerPresentation.background(for: .critical) == .red)
    }

    @Test("Warning, the default arm, is yellow rather than green")
    func warningIsNotReassuring() {
        // This used to assert `.unspecified` and `.UNRECOGNIZED(42)` too. The
        // REST contract's severity is a closed Swift enum with exactly the
        // three real values, so neither is representable any more — an
        // unrecognised value now fails to decode the response rather than
        // reaching this function. That is bounded by a database CHECK
        // constraint allowing only these three; see StatusBannerPresentation's
        // own doc comment. What is still worth pinning is that the `default`
        // arm resolves to yellow, not green.
        #expect(StatusBannerPresentation.background(for: .warning) == .yellow)
    }

    @Test("Foreground contrasts with its own background")
    func foregroundIsLegible() {
        // Yellow with white text is close to unreadable, and the banner that
        // has to be legible is the one saying something is wrong.
        #expect(StatusBannerPresentation.foreground(for: .warning) == .black)
        #expect(StatusBannerPresentation.foreground(for: .info) == .white)
        #expect(StatusBannerPresentation.foreground(for: .critical) == .white)
    }

    @Test("Informational and warning banners can be dismissed")
    func dismissibleSeverities() {
        #expect(StatusBannerPresentation.isDismissible(.info))
        #expect(StatusBannerPresentation.isDismissible(.warning))
    }

    @Test("A critical banner cannot be dismissed")
    func criticalIsPinned() {
        #expect(!StatusBannerPresentation.isDismissible(.critical))
    }

    @Test("An English reader gets the English text")
    func englishMessage() {
        #expect(StatusBannerPresentation.message(for: banner(), languageCode: "en") == "Bank syncing is delayed.")
    }

    @Test("A Spanish reader gets the Spanish text")
    func spanishMessage() {
        let text = StatusBannerPresentation.message(for: banner(), languageCode: "es")
        #expect(text == "La sincronización bancaria está retrasada.")
    }

    @Test("A regional locale still matches its language")
    func regionalLocaleMatches() {
        let text = StatusBannerPresentation.message(for: banner(), languageCode: "es-MX")
        #expect(text == "La sincronización bancaria está retrasada.")
    }

    @Test("Empty Spanish falls back to English rather than a blank bar")
    func fallsBackWhenSpanishMissing() {
        // message_es is optional server-side: an operator posting mid-incident
        // shouldn't be blocked on writing Spanish.
        let text = StatusBannerPresentation.message(for: banner(messageEs: ""), languageCode: "es")
        #expect(text == "Bank syncing is delayed.")
    }

    @Test("Whitespace-only Spanish counts as empty")
    func whitespaceSpanishFallsBack() {
        let text = StatusBannerPresentation.message(for: banner(messageEs: "   "), languageCode: "es")
        #expect(text == "Bank syncing is delayed.")
    }
}

@Suite("StatusBannerDismissalStore")
struct StatusBannerDismissalStoreTests {
    /// A throwaway suite name per test, so these never touch
    /// `UserDefaults.standard` or race the rest of the suite — the exact
    /// problem `AppLanguageStoreTests` has to work around with `.serialized`.
    private func makeStore() -> (StatusBannerDismissalStore, UserDefaults) {
        let suiteName = "StatusBannerDismissalStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (StatusBannerDismissalStore(defaults: defaults), defaults)
    }

    @Test("Nothing is dismissed to begin with")
    func startsEmpty() {
        let (store, _) = makeStore()
        #expect(!store.isDismissed("b1"))
    }

    @Test("A dismissed banner is remembered")
    func remembersDismissal() {
        let (store, _) = makeStore()
        store.markDismissed("b1")
        #expect(store.isDismissed("b1"))
    }

    @Test("Dismissing one banner does not suppress another")
    func dismissalIsPerBanner() {
        // Keying on the ID is the whole point: closing one notice must not
        // hide the next, unrelated one.
        let (store, _) = makeStore()
        store.markDismissed("b1")
        #expect(!store.isDismissed("b2"))
    }

    @Test("Earlier dismissals survive later ones")
    func keepsEarlierDismissals() {
        let (store, _) = makeStore()
        store.markDismissed("b1")
        store.markDismissed("b2")
        #expect(store.isDismissed("b1"))
        #expect(store.isDismissed("b2"))
    }

    @Test("Dismissing the same banner twice stores it once")
    func doesNotDuplicate() {
        let (store, _) = makeStore()
        store.markDismissed("b1")
        store.markDismissed("b1")
        #expect(store.dismissedIDs() == ["b1"])
    }

    @Test("The remembered list is capped so it cannot grow forever")
    func capsStoredHistory() {
        let (store, _) = makeStore()
        for i in 0..<30 { store.markDismissed("b\(i)") }

        #expect(store.dismissedIDs().count == 20)
        #expect(store.dismissedIDs().first == "b29")
        #expect(!store.isDismissed("b0"))
    }
}
