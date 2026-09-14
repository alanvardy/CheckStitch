@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ChecklistCreatorTests {
    @Test(arguments: [nil, "", "   ", "\n\n"] as [String?])
    func createSkipsBlankTitles(_ blank: String?) async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [
            makeItem("one"), makeItem(blank ?? ""), makeItem("two"),
        ])
        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["one", "two"])
    }

    @Test(arguments: ["t", "t "])
    func createReturnsCountForNonBlankItems(_ title: String) async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem(title)])
        #expect(outcome == .created(count: 1))
        #expect(spy.createdTitles == [title], "identical title must be preserved untrimmed")
    }

    @Test
    func allBlankItemsCreateNothing() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem(""), makeItem("  ")])
        #expect(outcome == .created(count: 0))
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func permissionDeniedReturnsOutcomeWithoutCreating() async {
        let spy = SpyReminderCreator()
        spy.accessGranted = false
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem("one")])
        #expect(outcome == .permissionDenied)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func accessErrorReturnsFailedWithoutCreating() async {
        let spy = SpyReminderCreator()
        spy.accessError = TestError.boom
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem("one")])
        #expect(outcome == .failed(TestError.boom.localizedDescription))
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func createStopsAndReportsFailureWhenSaveThrows() async {
        let spy = SpyReminderCreator()
        spy.createError = TestError.boom
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem("one"), makeItem("two")])
        #expect(outcome == .failed(TestError.boom.localizedDescription))
        #expect(spy.createdTitles.isEmpty)
    }

    /// Fixed, UTC gregorian calendar plus a fixed "today" so the components are
    /// exact. Built as locals (a `Date` is `Sendable`) rather than captured through
    /// `self`, because the creator's `now` closure must be `@Sendable`.
    @Test
    func relativeDatesCarryThroughToTheSeam() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy, now: { today }, calendar: calendar)
        let items = [
            ChecklistItem(title: "a", relativeDate: 0),
            ChecklistItem(title: "b", relativeDate: 1),
            ChecklistItem(title: "c"),
        ]

        let outcome = await creator.create(from: items)

        #expect(outcome == .created(count: 3))
        #expect(spy.createdItems.map { $0.title } == ["a", "b", "c"])
        #expect(spy.createdItems[0].dueDateComponents == DateComponents(year: 2026, month: 3, day: 10))
        #expect(spy.createdItems[1].dueDateComponents == DateComponents(year: 2026, month: 3, day: 11))
        #expect(spy.createdItems[2].dueDateComponents == nil)
    }

    @Test
    func blankItemsAreStillSkippedWhenTheyCarryDates() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy, now: { today }, calendar: calendar)

        let outcome = await creator.create(from: [
            ChecklistItem(title: "  ", relativeDate: 3),
            ChecklistItem(title: "a", relativeDate: -1),
        ])

        #expect(outcome == .created(count: 1))
        #expect(spy.createdItems.map { $0.title } == ["a"])
        #expect(spy.createdItems[0].dueDateComponents == DateComponents(year: 2026, month: 3, day: 9))
    }
}
