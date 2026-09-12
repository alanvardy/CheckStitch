@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ChecklistSyncCoordinatorTests {
    private func makeCoordinator(
        transport: FakeChecklistSyncTransport,
        checklists: [Checklist],
        runner: SpyChecklistRunner
    ) -> ChecklistSyncCoordinator {
        ChecklistSyncCoordinator(
            transport: transport,
            snapshot: { checklists },
            createReminders: { await runner.run($0) })
    }

    @Test
    func startPushesTheEncodedChecklistContext() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let checklists = [Checklist(name: "Groceries")]
        let coordinator = makeCoordinator(transport: transport, checklists: checklists, runner: runner)

        coordinator.start()

        #expect(transport.activateCount == 1)
        #expect(transport.sentContexts.count == 1)
        #expect(ChecklistCodec.decode(transport.sentContexts[0]) == checklists)
    }

    @Test
    func storeChangePushesAgain() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: runner)

        coordinator.start()
        coordinator.checklistsDidChange()

        #expect(transport.sentContexts.count == 2)
    }

    @Test
    func runRequestForKnownIDCreatesRemindersOnce() async {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")])
        let coordinator = makeCoordinator(transport: transport, checklists: [checklist], runner: runner)
        coordinator.start()

        transport.deliver(.runChecklist(checklist.id))
        for _ in 0..<50 where runner.created.isEmpty { await Task.yield() }

        #expect(runner.created == [checklist])
    }

    @Test
    func runRequestForUnknownIDCreatesNothing() async {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: runner)
        coordinator.start()

        transport.deliver(.runChecklist(UUID()))
        await Task.yield()

        #expect(runner.created.isEmpty)
    }

    @Test
    func requestChecklistsPushesAgain() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let coordinator = makeCoordinator(transport: transport, checklists: [], runner: runner)
        coordinator.start()

        transport.deliver(.requestChecklists)

        #expect(transport.sentContexts.count == 2)
    }

    @Test
    func activationSeedsTheWatchAfterTheColdStartDrop() {
        let transport = FakeChecklistSyncTransport()
        let runner = SpyChecklistRunner()
        let checklists = [Checklist(name: "Groceries")]
        let coordinator = makeCoordinator(transport: transport, checklists: checklists, runner: runner)

        // `start()` pushes before the session is usable, then activation completes.
        transport.acceptsSends = false
        coordinator.start()
        transport.acceptsSends = true
        transport.completeActivation()

        #expect(transport.sentContexts.count == 2)
        #expect(ChecklistCodec.decode(transport.sentContexts[1]) == checklists)
    }
}