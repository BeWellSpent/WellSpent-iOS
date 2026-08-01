import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PlanLabel")
struct PlanLabelTests {
    @Test("text maps every plan to its display name, unspecified reads as Free")
    func textMapsEveryCase() {
        #expect(PlanLabel.text(for: .unspecified) == "Free")
        #expect(PlanLabel.text(for: .free) == "Free")
        #expect(PlanLabel.text(for: .pro) == "Pro")
        #expect(PlanLabel.text(for: .lifetime) == "Lifetime")
    }

    @Test("systemImage uses a crown for Pro and Lifetime only")
    func systemImageDistinguishesPaidTiers() {
        #expect(PlanLabel.systemImage(for: .free) == "person")
        #expect(PlanLabel.systemImage(for: .pro) == "crown.fill")
        #expect(PlanLabel.systemImage(for: .lifetime) == "crown.fill")
    }
}
