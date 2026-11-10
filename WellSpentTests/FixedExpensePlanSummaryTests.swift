import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("FixedExpensePlanSummary")
struct FixedExpensePlanSummaryTests {
    private static let now = Date(timeIntervalSince1970: 1_786_622_400) // 2026-08-13

    private func expense(
        installment: Bool = false, totalPayments: Int32 = 0, paymentsMade: Int32 = 0, endInDays: Int? = nil
    ) -> Wellspent_V1_FixedExpense {
        .with {
            $0.isInstallmentPlan = installment
            $0.totalPayments = totalPayments
            $0.paymentsMade = paymentsMade
            if let endInDays {
                $0.endDate = Google_Protobuf_Timestamp(dateOnly: Calendar.current.date(byAdding: .day, value: endInDays, to: Self.now)!)
            }
        }
    }

    @Test("An open-ended bill has no kind, progress or end")
    func plainRecurringBill() {
        let plain = expense()
        #expect(FixedExpensePlanSummary.kind(for: plain) == nil)
        #expect(FixedExpensePlanSummary.progressText(for: plain) == nil)
        #expect(FixedExpensePlanSummary.endsText(for: plain, localeIdentifier: "en") == nil)
        #expect(!FixedExpensePlanSummary.isEndingSoon(plain, now: Self.now))
    }

    @Test("Card installments and other plans are told apart")
    func kinds() {
        #expect(FixedExpensePlanSummary.kind(for: expense(installment: true, totalPayments: 6)) == .installments)
        #expect(FixedExpensePlanSummary.kind(for: expense(totalPayments: 36)) == .paymentPlan)
        #expect(FixedExpensePlanSummary.kind(for: expense(endInDays: 400)) == .paymentPlan)
    }

    @Test("Progress reads made / total, and needs a total")
    func progress() {
        #expect(FixedExpensePlanSummary.progressText(for: expense(totalPayments: 12, paymentsMade: 7))?.contains("7 / 12") == true)
        #expect(FixedExpensePlanSummary.progressText(for: expense(endInDays: 30)) == nil)
    }

    @Test("Ending soon: within 60 days or with 2 or fewer payments left; not otherwise")
    func endingSoon() {
        #expect(FixedExpensePlanSummary.isEndingSoon(expense(endInDays: 59), now: Self.now))
        #expect(!FixedExpensePlanSummary.isEndingSoon(expense(endInDays: 200), now: Self.now))
        #expect(FixedExpensePlanSummary.isEndingSoon(expense(totalPayments: 12, paymentsMade: 10), now: Self.now))
        #expect(!FixedExpensePlanSummary.isEndingSoon(expense(totalPayments: 12, paymentsMade: 3), now: Self.now))
        #expect(FixedExpensePlanSummary.isEndingSoon(expense(endInDays: -3), now: Self.now)) // already past
    }
}
