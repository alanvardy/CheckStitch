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
}