import Foundation
import Observation
import WellSpentAPI
import WellSpentREST

@MainActor
@Observable
final class AddEditIncomeViewModel {
    enum Mode {
        case add
        case edit(IncomeJobGrouping.Job)
    }

    var name: String
    var incomeType: Wellspent_V1_IncomeType
    /// The whole job's total pay, as denominated (e.g. "$4,000/month") —
    /// not a single payday's amount. Split evenly across `payDates` at
    /// submit time (see `splitAmountText`/`MoneyInput.splitEvenly`).
    var amountText: String
    var recurring: Bool
    var personID: Int64
    var paymentFrequency: Wellspent_V1_RecurringType
    var beforeTax: Bool
    var earlyArrivalToleranceDays: Int
    /// Whole-job setting, not per-payday — mirrors `earlyArrivalToleranceDays`
    /// above. Meaningless for weekly/bi-weekly (`showWeekendAdjustmentToggle`
    /// hides it there), since those anchors have no month/day to land on a
    /// weekend in the first place.
    var adjustForWeekends: Bool

    /// One entry per payday. Empty = no regular schedule (irregular income).
    /// A job paid out more than once per period (e.g. semi-monthly) has more
    /// than one entry here, each becoming its own `IncomeSource` row sharing
    /// everything else above — see `IncomeJobGrouping`.
    private(set) var payDates: [Date]

    var hasPaySchedule: Bool { !payDates.isEmpty }
    var payDateCount: Int { payDates.count }

    /// Mirrors `AddFixedExpenseView`'s "Has end date" gating shape — shown
    /// only once there's a real recurring schedule to anchor (irregular/
    /// one-off income has nothing to schedule against).
    var showPayScheduleFields: Bool {
        recurring && paymentFrequency != .oneOff
    }

    /// Only monthly/yearly anchors can land on a weekend day-of-month — a
    /// weekly/bi-weekly anchor's day-of-week never changes, so the backend's
    /// own `adjustForWeekends` doc calls it "meaningless" there.
    var showWeekendAdjustmentToggle: Bool {
        paymentFrequency == .monthly || paymentFrequency == .yearly
    }

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    let mode: Mode
    let countryCode: String

    private let budgetProfileID: String
    private let currencyCode: String
    private let restClient: WellSpentREST.Client

    /// Matches the backend's `before_tax_income` country feature flag — only
    /// meaningful for US users (see docs/specs/03-data-model.md).
    var showBeforeTaxToggle: Bool {
        countryCode == "US"
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MoneyInput.parseAmount(amountText) != nil
            && !isSubmitting
    }

    init(mode: Mode, budgetProfileID: String, countryCode: String, currencyCode: String, restClient: WellSpentREST.Client) {
        self.mode = mode
        self.budgetProfileID = budgetProfileID
        self.countryCode = countryCode
        self.currencyCode = currencyCode
        self.restClient = restClient

        switch mode {
        case .add:
            name = ""
            incomeType = .salary
            amountText = ""
            recurring = true
            personID = 0
            paymentFrequency = .monthly
            beforeTax = false
            payDates = []
            earlyArrivalToleranceDays = 0
            adjustForWeekends = true
        case .edit(let job):
            let rows = IncomeJobGrouping.sortedRows(job.rows)
            let first = rows[0].source
            name = first.name
            incomeType = first.incomeType
            let total = job.totalAmount
            amountText = MoneyInput.formatForEditing(units: total.units, nanos: total.nanos)
            recurring = first.recurring
            personID = first.budgetPersonID
            paymentFrequency = first.paymentFrequency
            beforeTax = first.beforeTax
            earlyArrivalToleranceDays = Int(rows[0].schedule.earlyArrivalToleranceDays)
            adjustForWeekends = rows[0].schedule.adjustForWeekends
            let anchors = rows.compactMap(\.schedule.anchorDate)
            // Only treat this as a real schedule if every row actually has
            // one — a partial mix shouldn't happen by construction, but
            // falling back to "no schedule" rather than guessing is safer
            // than silently dropping a payday's date.
            payDates = (anchors.count == rows.count && !anchors.isEmpty) ? anchors : []
        }
    }

    /// Not private, so `AddEditIncomeView` can render a stable sheet of
    /// `DatePicker`s without `payDates` itself being publicly settable.
    func setHasPaySchedule(_ on: Bool) {
        payDates = on ? (payDates.isEmpty ? [Date()] : payDates) : []
    }

    func setPayDateCount(_ newValue: Int) {
        let clamped = max(1, min(4, newValue))
        if clamped > payDates.count {
            var next = payDates.last ?? Date()
            for _ in payDates.count..<clamped {
                next = Calendar.current.date(byAdding: .day, value: 15, to: next) ?? next
                payDates.append(next)
            }
        } else if clamped < payDates.count {
            payDates.removeLast(payDates.count - clamped)
        }
    }

    func setPayDate(at index: Int, to date: Date) {
        guard payDates.indices.contains(index) else { return }
        payDates[index] = date
    }

    /// The per-payday split of `amountText`, formatted for display next to
    /// each date picker — made visible rather than silent, since the user
    /// typed one total and this is what actually gets saved per row.
    func splitAmountText(at index: Int) -> String? {
        guard let amount = MoneyInput.parseAmount(amountText), payDates.indices.contains(index) else { return nil }
        let parts = MoneyInput.splitEvenly(units: amount.units, nanos: amount.nanos, count: payDates.count)
        guard parts.indices.contains(index) else { return nil }
        return MoneyFormatting.format(units: parts[index].units, nanos: parts[index].nanos, currencyCode: currencyCode, localeIdentifier: AppLanguageStore.currentLocale.identifier)
    }

    /// Returns whether the save fully succeeded. On `false`, the caller
    /// should still trigger a reload (some of a multi-payday save's calls
    /// may have already landed server-side) and keep the sheet open so the
    /// error is visible and the user can retry.
    func submit() async -> Bool {
        guard canSubmit, let amount = MoneyInput.parseAmount(amountText) else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let scheduled = showPayScheduleFields && hasPaySchedule
        let dates: [Date?] = scheduled ? payDates.sorted().map { Optional($0) } : [nil]
        let tolerance: Int32 = scheduled ? Int32(earlyArrivalToleranceDays) : 0
        let amounts = MoneyInput.splitEvenly(units: amount.units, nanos: amount.nanos, count: dates.count)

        switch mode {
        case .add:
            for (date, part) in zip(dates, amounts) {
                guard await createSource(anchorDate: date, toleranceDays: tolerance, amount: part) else { return false }
            }
            return true
        case .edit(let job):
            let existingIDs = IncomeJobGrouping.sortedRows(job.rows).map(\.source.id)
            for action in IncomeJobReconciliation.diff(existingCount: existingIDs.count, newDateCount: dates.count) {
                switch action {
                case .update(let existingIndex, let dateIndex):
                    guard await updateSource(id: existingIDs[existingIndex], anchorDate: dates[dateIndex], toleranceDays: tolerance, amount: amounts[dateIndex]) else { return false }
                case .add(let dateIndex):
                    guard await createSource(anchorDate: dates[dateIndex], toleranceDays: tolerance, amount: amounts[dateIndex]) else { return false }
                case .delete(let existingIndex):
                    guard await deleteSource(id: existingIDs[existingIndex]) else { return false }
                }
            }
            return true
        }
    }

    private func money(_ amount: (units: Int64, nanos: Int32)) -> Wellspent_V1_Money {
        .with { $0.units = amount.units; $0.nanos = amount.nanos; $0.currency = currencyCode }
    }

    private func createSource(anchorDate: Date?, toleranceDays: Int32, amount: (units: Int64, nanos: Int32)) async -> Bool {
        let fallback = "Couldn't add that income source."
        do {
            let output = try await restClient.addIncomeSource(.init(
                path: .init(id: budgetProfileID),
                body: .json(.init(
                    name: name.trimmingCharacters(in: .whitespaces),
                    incomeType: BudgetRESTMapping.restIncomeType(from: incomeType),
                    defaultAmount: BudgetRESTMapping.restMoney(from: money(amount)),
                    recurring: recurring,
                    budgetPersonId: personID,
                    paymentFrequency: BudgetRESTMapping.restRecurringFrequency(from: paymentFrequency),
                    beforeTax: showBeforeTaxToggle && beforeTax,
                    anchorDate: anchorDate.map { Google_Protobuf_Timestamp(dateOnly: $0).restDateString },
                    earlyArrivalToleranceDays: toleranceDays,
                    adjustForWeekends: adjustForWeekends
                ))
            ))
            guard case .ok = output else {
                errorMessage = fallback
                return false
            }
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return false
        }
    }

    private func updateSource(id: Int64, anchorDate: Date?, toleranceDays: Int32, amount: (units: Int64, nanos: Int32)) async -> Bool {
        let fallback = "Couldn't update that income source."
        do {
            let output = try await restClient.updateIncomeSource(.init(
                path: .init(id: budgetProfileID, sourceId: id),
                body: .json(.init(
                    name: name.trimmingCharacters(in: .whitespaces),
                    incomeType: BudgetRESTMapping.restIncomeType(from: incomeType),
                    defaultAmount: BudgetRESTMapping.restMoney(from: money(amount)),
                    recurring: recurring,
                    budgetPersonId: personID,
                    paymentFrequency: BudgetRESTMapping.restRecurringFrequency(from: paymentFrequency),
                    beforeTax: showBeforeTaxToggle && beforeTax,
                    anchorDate: anchorDate.map { Google_Protobuf_Timestamp(dateOnly: $0).restDateString },
                    earlyArrivalToleranceDays: toleranceDays,
                    adjustForWeekends: adjustForWeekends
                ))
            ))
            guard case .ok = output else {
                errorMessage = fallback
                return false
            }
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return false
        }
    }

    private func deleteSource(id: Int64) async -> Bool {
        let fallback = "Couldn't update that income source."
        do {
            guard case .ok = try await restClient.deleteIncomeSource(.init(path: .init(id: budgetProfileID, sourceId: id))) else {
                errorMessage = fallback
                return false
            }
            return true
        } catch {
            errorMessage = RESTNetworkError.connectivityMessage(for: error) ?? fallback
            return false
        }
    }
}
