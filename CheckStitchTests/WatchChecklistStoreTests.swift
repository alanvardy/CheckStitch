@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct WatchChecklistStoreTests {
    @Test
    func startActivatesTransport() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        #expect(transport.activateCount == 1)
    }

    @Test
    func contextReplacesTheChecklistList() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        let expected = [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])]
        transport.deliver(.context(try ChecklistCodec.encode(expected)))

        #expect(store.checklists == expected)
    }

    @Test
    func malformedContextLeavesThePreviousListIntact() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        let expected = [Checklist(name: "Groceries")]
        transport.deliver(.context(try ChecklistCodec.encode(expected)))
        transport.deliver(.context(Data("not json".utf8)))

        #expect(store.checklists == expected)
    }

    @Test
    func runSendsExactlyOneRunRequestAndRecordsIt() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")

        store.run(checklist)

        #expect(transport.sentMessages == [.runChecklist(checklist.id)])
        #expect(store.pendingRunID == checklist.id)
    }

    @Test
    func requestRefreshAsksThePhoneToResend() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)

        store.requestRefresh()

        #expect(transport.sentMessages == [.requestChecklists])
    }
}