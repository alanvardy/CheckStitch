import XCTest

final class CheckStitchUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property.
    override class var runsForEachTargetApplicationUIConfiguration: Bool { false }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndAccessibilitySmoke() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.buttons["createChecklistButton"].waitForExistence(timeout: 5),
            "Create-checklist button should render")
        XCTAssertTrue(app.buttons["settingsButton"].exists, "Settings button should render")

        // First launch shows the empty state; a re-used simulator with a
        // persisted store shows the list, so accept either row action.
        let rowAction = app.buttons["emptyStateCreateButton"].exists
            ? app.buttons["emptyStateCreateButton"]
            : app.buttons["createRemindersButton"]
        XCTAssertTrue(rowAction.exists, "A checklist row action should render")

        // Cheap, non-rendering categories only: .dynamicType/.hitRegion can hang
        // virtualized runners and are covered by unit suites (mirrors
        // SingleThreadUITests). The #if os(iOS) guard is required because the
        // scheme's macOS test phase still compiles this bundle, and macOS's
        // XCUIAccessibilityAuditType offers a different category set.
        #if os(iOS)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        #else
            try app.performAccessibilityAudit()
        #endif
    }

    @MainActor
    func testUITestingSeededListRendersARow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["CHECKSTITCH_UITEST_SEED"] = try Self.writeSeedFixture().path
        app.launch()
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'checklistRow-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Seeded row should render")
    }

    @MainActor
    func testUITestingOpenSettingsShowsSettingsSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-open-settings"]
        app.launch()
        // SettingsView's root is the settings menu; the Interface row is the
        // sheet's first entry and proves the sheet presented off the seam.
        XCTAssertTrue(app.descendants(matching: .any)["settingsInterfaceRow"]
            .waitForExistence(timeout: 5), "Settings sheet should present")
    }

    @MainActor
    func testUITestingOpenChecklistPushesDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-open-checklist", "0"]
        app.launchEnvironment["CHECKSTITCH_UITEST_SEED"] = try Self.writeSeedFixture().path
        app.launch()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5),
                      "A back button implies the detail screen was pushed")
    }

    private static func writeSeedFixture() throws -> URL {
        let json = """
        {"version":6,"deviceID":"uitest","checklists":[
          {"id":"11111111-1111-4111-8111-111111111111","name":"Weekend Trip",
           "items":[{"id":"11111111-1111-4111-8111-111111111101","title":"Book train tickets"}]}]}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("appstore-seed-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url, options: .atomic)
        return url
    }
}