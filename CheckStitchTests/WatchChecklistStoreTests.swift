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
        transport.deliver(.context(try ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: expected))))

        #expect(store.checklists == expected)
    }

    @Test
    func v2ContextStillPopulatesTheList() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        let expected = [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", relativeDate: 1)])]
        transport.deliver(.context(try ChecklistCodec.encode(
            ChecklistEnvelope(version: 2, deviceID: "phone", checklists: expected))))

        #expect(store.checklists == expected)
    }

    @Test
    func malformedContextLeavesThePreviousListIntact() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        let expected = [Checklist(name: "Groceries")]
        transport.deliver(.context(try ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: expected))))
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

    @Test
    func activationRequestsRefreshAfterTheColdStartDrop() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)

        store.start()
        transport.completeActivation()

        #expect(transport.sentMessages == [.requestChecklists])
    }

    @Test
    func rejectedRunIsNotRecordedAsPending() {
        let transport = FakeChecklistSyncTransport()
        transport.acceptsSends = false
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")

        #expect(store.run(checklist) == false)
        #expect(store.pendingRunID == nil)
    }

    @Test
    func destinationFieldSurvivesTheWatchTransport() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        let expected = [Checklist(name: "Groceries", destinationListIdentifier: "list-a")]
        transport.deliver(.context(try ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: expected))))

        #expect(store.checklists.first?.destinationListIdentifier == "list-a")
    }

    @Test
    func descriptionSurvivesTheWatchTransport() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let expected = [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", description: "2 litres")])]
        transport.deliver(.context(try ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: expected))))

        #expect(store.checklists.first?.items.first?.description == "2 litres")
    }
}
