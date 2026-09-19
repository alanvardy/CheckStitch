@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct SharedImportInboxTests {
    @Test
    func receivesSameURLOnce() {
        let inbox = SharedImportInbox.shared
        _ = inbox.consume()                       // isolate from other suites
        let url = URL(fileURLWithPath: "/tmp/a.json")

        inbox.receive(url: url)
        inbox.receive(url: url)

        #expect(inbox.pending?.url == url)
        #expect(inbox.consume()?.url == url)
        #expect(inbox.consume() == nil, "one arrival consumes exactly once")
    }

    @Test
    func coldStartArrivalConsumesOnce() {
        let inbox = SharedImportInbox.shared
        _ = inbox.consume()
        let url = URL(fileURLWithPath: "/tmp/cold.json")

        inbox.receive(url: url)                   // delegated before root exists
        #expect(inbox.pending != nil, "arrival survives until the root consumes")

        #expect(inbox.consume()?.displayName == "cold.json")
        #expect(inbox.pending == nil)
        #expect(inbox.consume() == nil)
    }

    @Test
    func secondDistinctArrivalReplacesPending() {
        let inbox = SharedImportInbox.shared
        _ = inbox.consume()
        let first = URL(fileURLWithPath: "/tmp/first.json")
        let second = URL(fileURLWithPath: "/tmp/second.json")

        inbox.receive(url: first)
        inbox.receive(url: second)

        #expect(inbox.consume()?.url == second)
        #expect(inbox.consume() == nil)
    }

    /// Deliberate (plan.md): `lastReceivedURL` survives `consume()` so a single
    /// delivery's double-fire (scene + delegate) cannot re-open the sheet.
    /// Re-opening the same URL later is therefore a silent no-op, not a second
    /// import — pinned here so the behaviour is not changed by accident.
    @Test
    func sameURLAfterConsumeIsDroppedByDesign() {
        let inbox = SharedImportInbox.shared
        _ = inbox.consume()                       // isolate from other suites
        let url = URL(fileURLWithPath: "/tmp/reopened.json")

        inbox.receive(url: url)
        #expect(inbox.consume()?.url == url)

        inbox.receive(url: url)
        #expect(inbox.pending == nil, "a re-shared identical URL is deliberately dropped")
    }
}
