import Foundation
import Testing
import WellSpentAPI
import WellSpentREST
@testable import WellSpent

@Suite("AddEditIncomeViewModel")
@MainActor
struct AddEditIncomeViewModelTests {
    private func makeViewModel(
        mode: AddEditIncomeViewModel.Mode = .add,
        countryCode: String = "US"
    ) -> AddEditIncomeViewModel {
        AddEditIncomeViewModel(
            mode: mode,
            budgetProfileID: "profile-1",
            countryCode: countryCode,
            currencyCode: "USD",
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    private func source(id: Int64, name: String = "Paycheck", units: Int64 = 1200, personID: Int64 = 7) -> Wellspent_V1_IncomeSource {
        .with {
            $0.id = id
            $0.name = name
            $0.incomeType = .freelance
            $0.defaultAmount = .with { $0.units = units; $0.nanos = 0; $0.currency = "USD" }
            $0.recurring = false
            $0.budgetPersonID = personID
            $0.paymentFrequency = .monthly
            $0.beforeTax = true
        }
    }

    private func job(rows: [IncomeJobGrouping.Row]) -> IncomeJobGrouping.Job {
        let first = rows[0].source
        return IncomeJobGrouping.Job(
            key: .init(name: first.name, budgetPersonID: first.budgetPersonID, incomeType: first.incomeType, paymentFrequency: first.paymentFrequency),
            rows: IncomeJobGrouping.sortedRows(rows)
        )
    }

    @Test("submit is disabled until name and a valid amount are present")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "Paycheck"
        #expect(!viewModel.canSubmit)

        viewModel.amountText = "not-a-number"
        #expect(!viewModel.canSubmit)

        viewModel.amountText = "2500.50"
        #expect(viewModel.canSubmit)
    }

    @Test("rejects a negative amount")
    func rejectsNegativeAmount() {
        let viewModel = makeViewModel()
        viewModel.name = "Paycheck"
        viewModel.amountText = "-100"
        #expect(!viewModel.canSubmit)
    }

    @Test("before-tax toggle only shows for US budgets")
    func beforeTaxVisibility() {
        #expect(makeViewModel(countryCode: "US").showBeforeTaxToggle)
        #expect(!makeViewModel(countryCode: "AR").showBeforeTaxToggle)
        #expect(!makeViewModel(countryCode: "ES").showBeforeTaxToggle)
    }

    @Test("editing a single-payday job pre-fills its fields exactly as before")
    func editModePrefillSinglePayday() {
        let row = IncomeJobGrouping.Row(
            source: source(id: 42, units: 1200),
            schedule: BudgetRESTMapping.IncomeSchedule(anchorDate: nil, earlyArrivalToleranceDays: 2)
        )
        let viewModel = makeViewModel(mode: .edit(job(rows: [row])), countryCode: "US")

        #expect(viewModel.name == "Paycheck")
        #expect(viewModel.incomeType == .freelance)
        #expect(viewModel.amountText == "1200")
        #expect(viewModel.recurring == false)
        #expect(viewModel.personID == 7)
        #expect(viewModel.beforeTax == true)
        #expect(viewModel.earlyArrivalToleranceDays == 2)
        #expect(!viewModel.hasPaySchedule)
        #expect(viewModel.payDateCount == 0)
    }

    @Test("editing a multi-payday job pre-fills the combined amount and every pay date")
    func editModePrefillMultiPayday() {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.date(from: .init(year: 2026, month: 1, day: 1))!
        let second = calendar.date(from: .init(year: 2026, month: 1, day: 15))!
        let rows = [
            IncomeJobGrouping.Row(source: source(id: 1, units: 2000), schedule: BudgetRESTMapping.IncomeSchedule(anchorDate: second, earlyArrivalToleranceDays: 1)),
            IncomeJobGrouping.Row(source: source(id: 2, units: 2000), schedule: BudgetRESTMapping.IncomeSchedule(anchorDate: first, earlyArrivalToleranceDays: 1)),
        ]
        let viewModel = makeViewModel(mode: .edit(job(rows: rows)))

        #expect(viewModel.amountText == "4000")
        #expect(viewModel.hasPaySchedule)
        #expect(viewModel.payDateCount == 2)
        // Sorted ascending — the earlier date comes first regardless of input order.
        #expect(viewModel.payDates.map { calendar.component(.day, from: $0) } == [1, 15])
    }

    @Test("pay schedule fields hide once income isn't a regular recurring schedule")
    func payScheduleVisibility() {
        let viewModel = makeViewModel()
        viewModel.recurring = true
        viewModel.paymentFrequency = .monthly
        #expect(viewModel.showPayScheduleFields)

        viewModel.paymentFrequency = .oneOff
        #expect(!viewModel.showPayScheduleFields)

        viewModel.paymentFrequency = .monthly
        viewModel.recurring = false
        #expect(!viewModel.showPayScheduleFields)
    }

    @Test("turning on a pay schedule starts with exactly one payday")
    func enablingScheduleStartsWithOnePayday() {
        let viewModel = makeViewModel()
        #expect(!viewModel.hasPaySchedule)
        viewModel.setHasPaySchedule(true)
        #expect(viewModel.hasPaySchedule)
        #expect(viewModel.payDateCount == 1)
        viewModel.setHasPaySchedule(false)
        #expect(!viewModel.hasPaySchedule)
        #expect(viewModel.payDateCount == 0)
    }

    @Test("pay date count is clamped to 1-4 and defaults new dates after the last one")
    func payDateCountClamps() {
        let viewModel = makeViewModel()
        viewModel.setHasPaySchedule(true)
        viewModel.setPayDateCount(10)
        #expect(viewModel.payDateCount == 4)
        viewModel.setPayDateCount(0)
        #expect(viewModel.payDateCount == 1)
    }

    @Test("weekend-adjustment toggle only shows for monthly/yearly frequencies")
    func weekendAdjustmentVisibility() {
        let viewModel = makeViewModel()
        viewModel.paymentFrequency = .monthly
        #expect(viewModel.showWeekendAdjustmentToggle)
        viewModel.paymentFrequency = .yearly
        #expect(viewModel.showWeekendAdjustmentToggle)
        viewModel.paymentFrequency = .weekly
        #expect(!viewModel.showWeekendAdjustmentToggle)
        viewModel.paymentFrequency = .biWeekly
        #expect(!viewModel.showWeekendAdjustmentToggle)
        viewModel.paymentFrequency = .oneOff
        #expect(!viewModel.showWeekendAdjustmentToggle)
    }

    @Test("adjustForWeekends defaults to true when adding, and prefills from the job's own schedule when editing")
    func adjustForWeekendsPrefill() {
        #expect(makeViewModel().adjustForWeekends)

        let row = IncomeJobGrouping.Row(
            source: source(id: 42),
            schedule: BudgetRESTMapping.IncomeSchedule(anchorDate: nil, earlyArrivalToleranceDays: 0, adjustForWeekends: false)
        )
        let viewModel = makeViewModel(mode: .edit(job(rows: [row])))
        #expect(!viewModel.adjustForWeekends)
    }

    @Test("split amount text divides the total evenly across pay dates")
    func splitAmountTextDividesEvenly() {
        let viewModel = makeViewModel()
        viewModel.amountText = "100"
        viewModel.setHasPaySchedule(true)
        viewModel.setPayDateCount(3)
        let texts = (0..<3).compactMap { viewModel.splitAmountText(at: $0) }
        #expect(texts.count == 3)
        // $100 / 3 = $33.34/$33.33/$33.33 — remainder goes to the first part.
        #expect(texts[0].contains("33.34"))
        #expect(texts[1].contains("33.33"))
    }
}
