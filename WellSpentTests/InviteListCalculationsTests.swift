import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("InviteListCalculations")
struct InviteListCalculationsTests {
    private func invite(email: String, expiresIn seconds: TimeInterval) -> Wellspent_V1_BudgetInvite {
        .with {
            $0.email = email
            $0.expiresAt = .init(date: Date(timeIntervalSince1970: seconds))
        }
    }

    @Test("keeps only the invite with the latest expiresAt for a repeated email")
    func keepsLatestPerEmail() {
        let older = invite(email: "a@example.com", expiresIn: 100)
        let newer = invite(email: "a@example.com", expiresIn: 200)

        let result = InviteListCalculations.latestPerEmail([older, newer])

        #expect(result.count == 1)
        #expect(result.first?.expiresAt.date == newer.expiresAt.date)
    }

    @Test("keeps distinct emails separately")
    func keepsDistinctEmails() {
        let a = invite(email: "a@example.com", expiresIn: 100)
        let b = invite(email: "b@example.com", expiresIn: 100)

        let result = InviteListCalculations.latestPerEmail([a, b])

        #expect(result.count == 2)
    }

    @Test("order of input doesn't matter")
    func orderIndependent() {
        let older = invite(email: "a@example.com", expiresIn: 100)
        let newer = invite(email: "a@example.com", expiresIn: 200)

        let result = InviteListCalculations.latestPerEmail([newer, older])

        #expect(result.count == 1)
        #expect(result.first?.expiresAt.date == newer.expiresAt.date)
    }
}
