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
}
