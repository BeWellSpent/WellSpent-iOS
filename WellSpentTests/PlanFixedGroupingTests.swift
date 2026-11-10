import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PlanFixedGrouping")
struct PlanFixedGroupingTests {
    private func template(_ id: String, totalPayments: Int32 = 0, installment: Bool = false, endInDays: Int? = nil) -> Wellspent_V1_FixedExpense {
        .with {
            $0.id = id
            $0.totalPayments = totalPayments
            $0.isInstallmentPlan = installment
            if let endInDays {
                $0.endDate = Google_Protobuf_Timestamp(dateOnly: Calendar.current.date(byAdding: .day, value: endInDays, to: Date())!)
            }
        }
    }

    @Test("Plans go first, ending soonest first; open-ended bills split by the server's due list")
    func groups() {
        let templates = [
            template("rent"),
            template("laptop", totalPayments: 6, installment: true, endInDays: 120),
            template("insurance"),
            template("car", totalPayments: 36, endInDays: 25),
        ]
        let groups = PlanFixedGrouping.group(templates, dueIDs: ["rent", "car", "laptop"])
        #expect(groups.plans.map(\.id) == ["car", "laptop"])
        #expect(groups.recurring.map(\.id) == ["rent"])
        #expect(groups.notDue.map(\.id) == ["insurance"])
    }

    @Test("Without the server's due list, no open-ended bill is guessed to be not due")
    func olderServer() {
        let groups = PlanFixedGrouping.group([template("rent"), template("insurance")], dueIDs: nil)
        #expect(groups.recurring.map(\.id) == ["rent", "insurance"])
        #expect(groups.notDue.isEmpty)
        #expect(PlanFixedGrouping.dueCount([template("rent")], dueIDs: nil) == nil)
    }

    @Test("Due count only counts templates the server says are due")
    func dueCount() {
        let templates = [template("rent"), template("insurance"), template("car", totalPayments: 36)]
        #expect(PlanFixedGrouping.dueCount(templates, dueIDs: ["rent", "car"]) == 2)
    }
}
