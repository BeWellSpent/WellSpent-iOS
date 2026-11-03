import Foundation
import WellSpentAPI

/// Explains, not changes, behavior: `IncomePeriodDates.ComputeNext` already
/// always picks whichever qualifying payday is soonest regardless of which
/// picker slot it's in, so entering pay day 1 as a later day-of-month than
/// pay day 2 (e.g. 1 = 31, 2 = 15) is handled correctly either way. But a
/// user reading "pay day 1" / "pay day 2" as literal chronological order
/// would be surprised that slot 1 lands *after* slot 2 within the same
/// calendar month — this surfaces that as a plain-language note instead of
/// leaving them to find out from the resulting period dates.
nonisolated enum PayDateOrderingHint {
    /// Only meaningful for monthly/yearly anchors with 2+ pay dates — a
    /// weekly/bi-weekly anchor is a day-of-week, where "day number"
    /// ordering has no such meaning.
    static func message(for dates: [Date], frequency: Wellspent_V1_RecurringType) -> String? {
        guard frequency == .monthly || frequency == .yearly, dates.count >= 2 else { return nil }
        guard let firstDay = dates.first.map(IncomePayDateInput.dayOfMonth(from:)) else { return nil }
        guard let earlierIndex = dates.dropFirst().firstIndex(where: { IncomePayDateInput.dayOfMonth(from: $0) < firstDay }) else { return nil }
        let earlierDay = IncomePayDateInput.dayOfMonth(from: dates[earlierIndex])
        return String(
            localized: "Pay day 1 (\(DayOfMonthLabel.text(for: firstDay))) falls after pay day \(earlierIndex + 1) (\(DayOfMonthLabel.text(for: earlierDay))) within the same calendar month — so pay day 1 is actually the previous month's last payment, not this month's first. Is that right?",
            bundle: AppLanguageStore.currentBundle,
            locale: AppLanguageStore.currentLocale
        )
    }
}
