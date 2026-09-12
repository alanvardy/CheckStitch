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
}