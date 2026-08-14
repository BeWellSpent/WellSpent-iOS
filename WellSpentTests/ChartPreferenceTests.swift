import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("ChartPreference")
struct ChartPreferenceTests {
    private func person(userID: String, plan: Wellspent_V1_ChartType = .unspecified, overview: Wellspent_V1_ChartType = .unspecified) -> Wellspent_V1_BudgetPerson {
        .with {
            $0.userID = userID
            $0.planChartType = plan
            $0.overviewChartType = overview
        }
    }

    @Test("an unset preference falls back to pie rather than rendering nothing")
    func unspecifiedFallsBackToPie() {
        #expect(ChartPreference.chartType(for: .unspecified) == .pie)
        #expect(ChartPreference.fallback == .pie)
    }

    @Test("a stored preference is honoured")
    func storedPreferenceHonoured() {
        #expect(ChartPreference.chartType(for: .bar) == .bar)
        #expect(ChartPreference.chartType(for: .pie) == .pie)
    }

    @Test("round-trips through the wire type")
    func roundTrips() {
        #expect(ChartPreference.chartType(for: ChartPreference.stored(for: .bar)) == .bar)
        #expect(ChartPreference.chartType(for: ChartPreference.stored(for: .pie)) == .pie)
    }

    @Test("resolves the caller's own row, never another member's")
    func resolvesOwnRow() {
        let people = [
            person(userID: "other", plan: .bar),
            person(userID: "me", plan: .pie),
        ]
        let me = ChartPreference.myPerson(currentUserID: "me", people: people)
        #expect(me?.userID == "me")
        #expect(me?.planChartType == .pie)
    }

    @Test("an unlinked placeholder is never matched")
    func placeholderNotMatched() {
        // An unlinked person has an empty user ID; a signed-out or unresolved
        // caller must not accidentally match it.
        let people = [person(userID: ""), person(userID: "")]
        #expect(ChartPreference.myPerson(currentUserID: "", people: people) == nil)
        #expect(ChartPreference.myPerson(currentUserID: nil, people: people) == nil)
        #expect(ChartPreference.myPerson(currentUserID: "me", people: people) == nil)
    }

    @Test("a non-member gets the default rather than someone else's setting")
    func nonMemberGetsDefault() {
        let people = [person(userID: "other", plan: .bar, overview: .bar)]
        let me = ChartPreference.myPerson(currentUserID: "me", people: people)
        #expect(me == nil)
        #expect(ChartPreference.chartType(for: me?.planChartType ?? .unspecified) == .pie)
    }
}
