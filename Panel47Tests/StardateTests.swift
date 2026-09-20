import Foundation
import Testing
@testable import Panel47

struct StardateTests {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar().date(from: components)!
    }

    @Test func startOfYearIsWholeThousand() {
        let value = Stardate.value(for: utcDate(2026, 1, 1), calendar: utcCalendar())
        #expect(abs(value - 26000.0) < 0.1)
    }

    @Test func midyearIsRoughlyHalfway() {
        // 2026 is not a leap year; July 2 is day 183 of 365, ~half the year.
        let value = Stardate.value(for: utcDate(2026, 7, 2), calendar: utcCalendar())
        #expect(abs(value - 26500.0) < 2.0)
    }

    @Test func laterYearsProduceLargerStardates() {
        let earlier = Stardate.value(for: utcDate(2026, 1, 1), calendar: utcCalendar())
        let later = Stardate.value(for: utcDate(2027, 1, 1), calendar: utcCalendar())
        #expect(later > earlier)
        #expect(abs(later - earlier - 1000) < 0.1)
    }

    @Test func timeOfDayAdvancesTheStardateWithinAYear() {
        let midnight = Stardate.value(for: utcDate(2026, 3, 15, 0), calendar: utcCalendar())
        let noon = Stardate.value(for: utcDate(2026, 3, 15, 12), calendar: utcCalendar())
        #expect(noon > midnight)
    }

    @Test func stringFormatHasOneDecimalPlace() {
        let text = Stardate.string(for: utcDate(2026, 1, 1), calendar: utcCalendar())
        #expect(text.contains("."))
        #expect(text.hasSuffix(".0") || text.split(separator: ".").last?.count == 1)
    }
}
