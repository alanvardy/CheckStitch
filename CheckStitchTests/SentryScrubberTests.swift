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
}
