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
    func runSendsOneRunRequestCarryingAFreshRunID() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")

        let runID = try #require(store.run(checklist))

        #expect(transport.sentMessages == [.runChecklist(id: checklist.id, runID: runID)])
        #expect(store.pendingRunID == runID)
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
    func aRejectedSendStartsNoRun() {
        let transport = FakeChecklistSyncTransport()
        transport.acceptsSends = false
        let store = WatchChecklistStore(transport: transport)

        #expect(store.run(Checklist(name: "Groceries")) == nil)
        #expect(store.pendingRunID == nil)
    }

    @Test
    func runEntersSendingAndCreatedConfirmsIt() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")

        let runID = try #require(store.run(checklist))
        #expect(store.runPhase(runID: runID) == .sending)

        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .created(2))))

        #expect(store.runPhase(runID: runID) == .created(2))
        #expect(store.pendingRunID == nil)
    }

    @Test
    func failedResultShowsAReasonAndKeepsTheRunOutOfPending() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")

        let runID = try #require(store.run(checklist))
        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .permissionDenied)))

        #expect(store.runPhase(runID: runID) == .failed(RunResultKind.permissionDenied.message))
        #expect(store.pendingRunID == nil)
    }

    @Test
    func resultForAnUnknownRunIsIgnored() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        transport.deliver(.runResult(RunResult(runID: UUID(), checklistID: UUID(), kind: .failed)))

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

    @Test
    func fieldClocksSurviveTheWatchContext() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        let reference = Date(timeIntervalSinceReferenceDate: 30)
        let older = Date(timeIntervalSinceReferenceDate: 10)
        let expected = [Checklist(name: "Groceries", items: [
            ChecklistItem(id: UUID(), title: "Milk", modifiedAt: reference, revision: 3,
                          titleRevision: 3, titleModifiedAt: reference,
                          descriptionRevision: 2, descriptionModifiedAt: older,
                          relativeDateRevision: 3, relativeDateModifiedAt: reference),
        ])]
        transport.deliver(.context(try ChecklistCodec.encode(ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "", checklists: expected))))

        let stored = try #require(store.checklists.first?.items.first)
        #expect(stored.titleRevision == 3)
        #expect(stored.titleModifiedAt == reference)
        #expect(stored.descriptionRevision == 2)
        #expect(stored.descriptionModifiedAt == older)
        #expect(stored.relativeDateRevision == 3)
        #expect(stored.relativeDateModifiedAt == reference)
    }
}
