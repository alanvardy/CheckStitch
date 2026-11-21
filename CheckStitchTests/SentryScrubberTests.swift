import Foundation
import Sentry
@testable import CheckStitch
import Testing

struct SentryScrubberTests {
    @Test
    func reminderContentIsRemovedFromEvent() {
        let event = Event()
        event.extra = ["reminderTitle": "Buy milk", "note": "2%"]
        event.user = User(userId: "Buy milk")
        event.tags = ["reminderTitle": "Buy milk", "environment": "debug"]

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed?.extra == nil)
        #expect(scrubbed?.user == nil)
        #expect(scrubbed?.tags?["reminderTitle"] == nil)
        #expect(scrubbed?.tags?["environment"] == "debug") // allow-listed field survives
    }

    @Test
    func reminderContentIsRemovedFromBreadcrumb() {
        let breadcrumb = Breadcrumb(level: .info, category: "reminder")
        breadcrumb.type = "navigation"
        breadcrumb.message = "Buy milk from the Grocery list"
        breadcrumb.setData(value: "2%", key: "note")
        breadcrumb.setData(value: "Grocery", key: "listName")

        let scrubbed = SentryScrubber.scrub(breadcrumb)

        #expect(scrubbed?.message == nil)
        #expect(scrubbed?.data == nil)
        #expect(scrubbed?.category == "reminder") // benign structural field survives
        #expect(scrubbed?.type == "navigation") // structural type survives, message does not
    }

    @Test
    func eventWithoutTagsStaysClean() {
        let event = Event()

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed != nil)
        #expect(scrubbed?.extra == nil)
        #expect(scrubbed?.user == nil)
    }

    @Test
    func breadcrumbWithoutDataSurvives() {
        let breadcrumb = Breadcrumb(level: .info, category: "reminder")

        let scrubbed = SentryScrubber.scrub(breadcrumb)

        #expect(scrubbed != nil)
        #expect(scrubbed?.category == "reminder")
        #expect(scrubbed?.data == nil)
    }

    @Test
    func exceptionReasonIsRemovedButTypeSurvives() {
        let event = Event()
        event.exceptions = [Exception(
            value: "Buy milk from the Grocery list",
            type: "NSInternalInconsistencyException")]

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed?.exceptions?.first?.value == nil)
        #expect(scrubbed?.exceptions?.first?.type == "NSInternalInconsistencyException")
    }

    @Test
    func eventMessageAndTransactionAreRemoved() {
        let event = Event()
        event.message = SentryMessage(formatted: "Buy milk from the Grocery list")
        event.transaction = "reminder.detail"

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed?.message == nil)
        #expect(scrubbed?.transaction == nil)
    }

    // MARK: App-hang system-stall predicate

    @Test
    func dropsCapturedGuidedAccessSystemStall() {
        #expect(SentryScrubber.scrub(hangEvent(frames: Self.capturedFrames)) == nil)
    }

    @Test
    func keepsHangWithAppFrameInBlockedChain() {
        var frames = Self.capturedFrames
        frames[frames.count - 1] = (Self.appImage, true) // app is the blocked (deepest) frame
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    // MARK: Fixtures

    private static let appImage =
        "/private/var/containers/Bundle/Application/277152F6-B99C-4FA0-BADB-098D8D06EC13/CheckStitch.app/CheckStitch"
    private static let swiftUI = "/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
    private static let uiKit = "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"
    private static let graphicsServices =
        "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices"
    private static let coreFoundation =
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    private static let accessibilitySettingsLoader =
        "/System/Library/AccessibilityBundles/AccessibilitySettingsLoader.bundle/AccessibilitySettingsLoader"
    private static let libDispatch = "/usr/lib/system/libdispatch.dylib"
    private static let foundation = "/System/Library/Frameworks/Foundation.framework/Foundation"
    private static let libSystemKernel = "/usr/lib/system/libsystem_kernel.dylib"

    /// The VAR-1183 event's client-side exception stack (`package` + `in_app`),
    /// outermost → innermost, as captured in the Linear ticket (`design.md`).
    private static let capturedFrames: [(image: String, inApp: Bool)] = [
        ("dyld", false),
        (appImage, true),
        (swiftUI, false),
        (uiKit, false),
        (graphicsServices, false),
        (coreFoundation, false),
        (accessibilitySettingsLoader, false),
        (libDispatch, false),
        (foundation, false),
        (libSystemKernel, false)
    ]

    private func hangEvent(
        frames: [(image: String, inApp: Bool)],
        mechanismType: String = "AppHang") -> Event {
        let event = Event()
        let exception = Exception(value: "App hanging.", type: "App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: mechanismType)
        exception.stacktrace = SentryStacktrace(frames: frames.map { frame in
            let sentryFrame = Frame()
            sentryFrame.package = frame.image
            // Sentry's `Frame.inApp` is SDK-mandated NSNumber.
            // swiftlint:disable:next legacy_objc_type
            sentryFrame.inApp = NSNumber(value: frame.inApp)
            return sentryFrame
        }, registers: [:])
        event.exceptions = [exception]
        return event
    }
}
