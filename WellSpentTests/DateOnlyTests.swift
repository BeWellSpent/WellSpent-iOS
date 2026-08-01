import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("DateOnly")
struct DateOnlyTests {
    /// A fixed UTC-midnight instant for August 1st, independent of the
    /// machine running the test's own timezone.
    private var utcMidnightAug1: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
    }

    @Test("local(fromUTCMidnight:) preserves the UTC calendar day, not the raw instant")
    func localPreservesUTCCalendarDay() {
        let local = DateOnly.local(fromUTCMidnight: utcMidnightAug1)

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let components = localCalendar.dateComponents([.year, .month, .day], from: local)

        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 1)
    }

    @Test("utcMidnight(fromLocal:) round-trips back through local(fromUTCMidnight:) to the same calendar day")
    func roundTripPreservesCalendarDay() {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let pickedLocalDay = localCalendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        let wireValue = DateOnly.utcMidnight(fromLocal: pickedLocalDay)
        let readBack = DateOnly.local(fromUTCMidnight: wireValue)

        let originalComponents = localCalendar.dateComponents([.year, .month, .day], from: pickedLocalDay)
        let readBackComponents = localCalendar.dateComponents([.year, .month, .day], from: readBack)
        #expect(originalComponents.year == readBackComponents.year)
        #expect(originalComponents.month == readBackComponents.month)
        #expect(originalComponents.day == readBackComponents.day)
    }

    @Test("Google_Protobuf_Timestamp.dateOnly matches DateOnly.local(fromUTCMidnight:)")
    func timestampExtensionMatchesFreeFunction() {
        let timestamp = Google_Protobuf_Timestamp(date: utcMidnightAug1)
        #expect(timestamp.dateOnly == DateOnly.local(fromUTCMidnight: utcMidnightAug1))
    }

    @Test("Google_Protobuf_Timestamp(dateOnly:) matches DateOnly.utcMidnight(fromLocal:)")
    func timestampInitMatchesFreeFunction() {
        let local = Date()
        let timestamp = Google_Protobuf_Timestamp(dateOnly: local)
        #expect(timestamp.date == DateOnly.utcMidnight(fromLocal: local))
    }
}
