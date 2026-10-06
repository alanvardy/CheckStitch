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

    /// Preview parity: a disabled item is dropped, exactly like a blank one.
    @Test
    func disabledItemsAreSkipped() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [
            makeItem("one"), makeItem("two", isEnabled: false),
        ])
        #expect(outcome == .created(count: 1))
        #expect(spy.createdTitles == ["one"])
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

    @Test
    func numberingIsOffByDefault() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy)
        let outcome = await creator.create(from: [makeItem("one"), makeItem("two")])
        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["one", "two"])
    }

    @Test
    func numberingPrefixesTitlesWithTheirPosition() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
        let outcome = await creator.create(from: [makeItem("one"), makeItem("two")])
        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["1: one", "2: two"])
    }

    @Test
    func numberingSkipsBlankItemsWithoutGaps() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
        let outcome = await creator.create(from: [
            makeItem("one"), makeItem(""), makeItem("two"), makeItem("   "),
        ])
        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["1: one", "2: two"])
    }

    /// Preview parity: a disabled item is dropped before numbering, so the
    /// preview shows contiguous positions across it with no gap.
    @Test
    func numberingSkipsDisabledItemsWithoutGaps() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
        let outcome = await creator.create(from: [
            makeItem("one"), makeItem("skip", isEnabled: false), makeItem("two"),
        ])
        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["1: one", "2: two"])
    }

    @Test
    func numberingContinuesPastNine() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
        let items = (1...10).map { makeItem("item \($0)") }
        let outcome = await creator.create(from: items)
        #expect(outcome == .created(count: 10))
        #expect(spy.createdTitles.first == "01: item 1")
        #expect(spy.createdTitles[4] == "05: item 5")
        #expect(spy.createdTitles.last == "10: item 10")
    }

    @Test
    func numberingStaysUnpaddedUpToNine() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
        let items = (1...9).map { makeItem("item \($0)") }
        let outcome = await creator.create(from: items)
        #expect(outcome == .created(count: 9))
        #expect(spy.createdTitles.first == "1: item 1")
        #expect(spy.createdTitles.last == "9: item 9")
    }

    /// Sad path: numbering must not bypass the permission gate.
    @Test
    func numberingStillRespectsPermissionDenial() async {
        let spy = SpyReminderCreator()
        spy.accessGranted = false
        let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
        let outcome = await creator.create(from: [makeItem("one")])
        #expect(outcome == .permissionDenied)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test(arguments: [("((3))", 2, "6"), ("((0))", 5, "0"), ("x ((2)) y", 3, "x 6 y")])
    func resolveScalesMarkers(_ text: String, _ multiple: Int, _ expected: String) {
        #expect(ChecklistScaling.resolve(text, multiple: multiple) == expected)
    }

    @Test(arguments: ["((abc))", "(x)", "((3)", "3))", "((3)))"])
    func nonMarkersPassThroughByteForByte(_ text: String) {
        #expect(ChecklistScaling.resolve(text, multiple: 4) == text)
    }

    @Test
    func overflowingDigitsPassThrough() {
        let text = "((99999999999999999999))"
        #expect(ChecklistScaling.resolve(text, multiple: 2) == text)
    }

    @Test
    func multipleOneIsAFastPath() {
        #expect(ChecklistScaling.resolve("((2)) raw", multiple: 1) == "((2)) raw")
    }

    @Test
    func titleIsScaledThenPrefixed() {
        let scaled = ChecklistScaling.resolve("milk ((2))", multiple: 3)
        #expect(ChecklistTitleNumbering.title(scaled, position: 1, numbered: true, itemCount: 1) == "1: milk 6")
    }

    /// Path B: the test-only creator applies scaling before its positional prefix.
    @Test
    func createScalesTitlesWhenMultipleProvided() async {
        let spy = SpyReminderCreator()
        let creator = ChecklistCreator(reminders: spy, prefixNumbers: true)
        let outcome = await creator.create(from: [makeItem("milk ((2))")], multiple: 5)
        #expect(outcome == .created(count: 1))
        #expect(spy.createdTitles == ["1: milk 10"])
    }
}
