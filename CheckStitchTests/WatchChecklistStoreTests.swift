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

        let runID = store.run(checklist)

        #expect(transport.sentMessages == [.runChecklist(id: checklist.id, runID: runID)])
        #expect(store.pendingRuns[runID]?.checklistID == checklist.id)
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
    func runBeforeActivationIsRetainedThenResentExactlyOnceOnActivation() throws {
        let transport = FakeChecklistSyncTransport()
        transport.acceptsSends = false
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")
        store.start()

        let runID = store.run(checklist)
        #expect(store.pendingRuns[runID]?.checklistID == checklist.id)

        transport.acceptsSends = true
        transport.completeActivation()

        let runSends = transport.sentMessages.filter { if case .runChecklist = $0 { return true }; return false }
        #expect(runSends == [
            .runChecklist(id: checklist.id, runID: runID),   // the rejected first attempt
            .runChecklist(id: checklist.id, runID: runID),   // the activation re-send
        ])
    }

    @Test
    func aResultClearsThePendingRun() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")
        let runID = store.run(checklist)

        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .created(1))))

        #expect(store.pendingRuns.isEmpty)
        #expect(store.runPhase(runID: runID) == .created(1))
    }

    @Test
    func aRejectedResendLeavesTheRunPending() {
        let transport = FakeChecklistSyncTransport()
        transport.acceptsSends = false
        let store = WatchChecklistStore(transport: transport)
        let checklist = Checklist(name: "Groceries")
        store.start()
        let runID = store.run(checklist)

        transport.completeActivation()   // still refusing sends

        #expect(store.pendingRuns[runID] != nil)
    }

    @Test
    func runEntersSendingAndCreatedConfirmsIt() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")

        let runID = store.run(checklist)
        #expect(store.runPhase(runID: runID) == .sending)

        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .created(2))))

        #expect(store.runPhase(runID: runID) == .created(2))
        #expect(store.pendingRuns.isEmpty)
    }

    @Test
    func failedResultShowsAReasonAndKeepsTheRunOutOfPending() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")

        let runID = store.run(checklist)
        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .permissionDenied)))

        #expect(store.runPhase(runID: runID) == .failed(RunResultKind.permissionDenied.message))
        #expect(store.pendingRuns.isEmpty)
    }

    @Test
    func resultForAnUnknownRunIsIgnored() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()

        transport.deliver(.runResult(RunResult(runID: UUID(), checklistID: UUID(), kind: .failed)))

        #expect(store.pendingRuns.isEmpty)
    }

    @Test
    func notFoundResultAsksForAFreshContext() throws {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")

        let runID = store.run(checklist)
        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: .notFound)))

        #expect(transport.sentMessages.contains(.requestChecklists))
        #expect(store.runPhase(runID: runID) == .failed(RunResultKind.notFound.message))
        #expect(store.pendingRuns.isEmpty)
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

    @Test(arguments: [
        (RunResultKind.created(3), RunPhase.created(3)),
        (.partiallyCreated(created: 2, total: 5), .partiallyCreated(created: 2, total: 5)),
        (.permissionDenied, .failed(RunResultKind.permissionDenied.message)),
        (.destinationMissing, .failed(RunResultKind.destinationMissing.message)),
        (.notFound, .failed(RunResultKind.notFound.message)),
        (.failed, .failed(RunResultKind.failed.message)),
    ])
    func everyResultKindMapsToAUserVisiblePhase(kind: RunResultKind, phase: RunPhase) {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")
        let runID = store.run(checklist)

        transport.deliver(.runResult(RunResult(runID: runID, checklistID: checklist.id, kind: kind)))

        #expect(store.runPhase(runID: runID) == phase)
    }

    @Test
    func tappingTheSameChecklistWhileARunIsPendingReusesThatRun() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")

        let first = store.run(checklist)
        let second = store.run(checklist)

        #expect(second == first)
        #expect(store.pendingRuns.count == 1)
        let runSends = transport.sentMessages.filter { if case .runChecklist = $0 { return true }; return false }
        #expect(runSends.count == 1)
    }

    @Test
    func aSecondRunIsAllowedOnceTheFirstHasAResult() {
        let transport = FakeChecklistSyncTransport()
        let store = WatchChecklistStore(transport: transport)
        store.start()
        let checklist = Checklist(name: "Groceries")

        let first = store.run(checklist)
        transport.deliver(.runResult(RunResult(runID: first, checklistID: checklist.id, kind: .created(1))))
        let second = store.run(checklist)

        #expect(second != first)
        #expect(store.pendingRuns.count == 1)
    }

    @Test(arguments: [
        (RunPhase.created(3), "Created 3 reminders." as String?),
        (RunPhase.partiallyCreated(created: 2, total: 5), "Created 2 of 5 reminders." as String?),
        (RunPhase.failed("boom"), "boom" as String?),
        (RunPhase.idle, String?.none),
        (RunPhase.sending, String?.none),
    ])
    func runPhaseDetailReportsCountsAndReasons(phase: RunPhase, detail: String?) {
        #expect(phase.detail == detail)
    }
}
