@testable import CheckStitchCore
import Foundation
import Testing

struct ChecklistItemDateTests {
    /// Fixed calendar + zone so the arithmetic is deterministic everywhere.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test
    func noOffsetYieldsNoDate() {
        #expect(ChecklistItem(title: "x").dueDateComponents(today: date(2026, 3, 10), calendar: calendar) == nil)
    }

    @Test(arguments: [(0, 10), (1, 11), (-1, 9)])
    func offsetMovesWholeDays(_ offset: Int, _ expectedDay: Int) {
        let components = ChecklistItem(title: "x", relativeDate: offset)
            .dueDateComponents(today: date(2026, 3, 10), calendar: calendar)
        #expect(components == DateComponents(year: 2026, month: 3, day: expectedDay))
    }

    @Test
    func offsetCrossesAMonthBoundary() {
        let components = ChecklistItem(title: "x", relativeDate: 1)
            .dueDateComponents(today: date(2026, 1, 31), calendar: calendar)
        #expect(components == DateComponents(year: 2026, month: 2, day: 1))
    }

    @Test
    func offsetCrossesAYearBoundary() {
        let components = ChecklistItem(title: "x", relativeDate: -1)
            .dueDateComponents(today: date(2026, 1, 1), calendar: calendar)
        #expect(components == DateComponents(year: 2025, month: 12, day: 31))
    }

    /// Just before local midnight still yields that local day (`startOfDay`).
    @Test
    func lateInTheDayStillYieldsThatDay() {
        let components = ChecklistItem(title: "x", relativeDate: 0)
            .dueDateComponents(today: date(2026, 3, 10, 23, 59), calendar: calendar)
        #expect(components == DateComponents(year: 2026, month: 3, day: 10))
    }

    @Test
    func resultCarriesNoTimeComponents() {
        let components = ChecklistItem(title: "x", relativeDate: 2)
            .dueDateComponents(today: date(2026, 3, 10), calendar: calendar)
        #expect(components?.hour == nil)
        #expect(components?.minute == nil)
        #expect(components?.second == nil)
    }
}