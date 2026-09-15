import CheckStitchCore
import Foundation
import Testing
@testable import CheckStitch

@MainActor
struct ChecklistSyncServiceTests {
    /// Fresh, uniquely-named suite per test so tests cannot bleed into each other.
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create test UserDefaults suite \(suiteName)")
        }
        return (defaults, suiteName)
    }

    /// Synchronous store persistence so assertions can run right after a
    /// mutation; the debounce itself is covered by the store suite.
    private func makeStore(defaults: UserDefaults) -> ChecklistStore {
        ChecklistStore(defaults: defaults, textEditDelay: nil)
    }

    /// `pushDelay: nil` so the debounce never races a test's assertions.
    private func makeService(sync: InMemoryChecklistSync, store: ChecklistStore) -> ChecklistSyncService {
        ChecklistSyncService(sync: sync, store: store, pushDelay: nil)
    }

    @Test
    func emptyCloudSeedsNonEmptyLocal() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        _ = store.create()
        let sync = InMemoryChecklistSync()
        let service = makeService(sync: sync, store: store)

        _ = await service.syncOnLaunch()

        #expect(service.lastOutcome == .seeded)
        #expect(sync.synchronizeCount >= 1, "a pull is requested before the first read")
        #expect(sync.written.count == 1, "the local envelope is pushed once")

        let second = await service.reconcile()
        #expect(second == .synced, "a seeded cloud reconciles cleanly")
        #expect(sync.written.count == 1, "the seeded payload is not written again")
    }

    @Test
    func emptyCloudWithEmptyLocalIsNotSeeded() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let sync = InMemoryChecklistSync()
        let service = makeService(sync: sync, store: store)

        let outcome = await service.syncOnLaunch()

        #expect(outcome == .synced, "an empty local payload must never be pushed over unseen cloud data")
        #expect(sync.written.isEmpty, "nothing is written when there is nothing to seed")
    }

    @Test
    func cloudV1PayloadIsMigratedOnReconcile() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let legacyID = UUID()
        let legacy = Data(#"{"version":1,"checklists":[{"id":"\#(legacyID.uuidString)","name":"Groceries","items":[]}]}"#.utf8)
        let sync = InMemoryChecklistSync(stored: legacy)
        let service = makeService(sync: sync, store: store)

        let outcome = await service.reconcile()

        #expect(outcome == .synced)
        #expect(store.checklists.map(\.id) == [legacyID], "a legacy cloud payload is migrated and absorbed")
        #expect(store.checklists.first?.revision == 1, "migration stamps a revision")
    }

    @Test
    func cloudV2PayloadIsAbsorbedWithoutRestampingOrTombstoneLoss() async throws {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let remoteID = UUID()
        let checklistID = UUID()
        let tombstone = ChecklistTombstone(
            checklistID: checklistID, itemID: nil, deletedAt: Date(timeIntervalSince1970: 99), revision: 2)
        let payload = ChecklistEnvelope(
            version: 2,
            deviceID: "remote-device",
            checklists: [Checklist(id: remoteID, name: "Remote", modifiedAt: Date(timeIntervalSince1970: 50), revision: 4)],
            tombstones: [tombstone])
        let sync = InMemoryChecklistSync(stored: try ChecklistCodec.encode(payload))
        let service = makeService(sync: sync, store: store)

        let outcome = await service.reconcile()

        #expect(outcome == .synced)
        #expect(store.checklists.first(where: { $0.id == remoteID })?.revision == 4, "v2 revisions are not restamped")
        #expect(store.checklists.first(where: { $0.id == remoteID })?.orderRevision == 4, "v2 ordering is seeded")
        #expect(store.tombstones.contains(tombstone), "v2 tombstones are not dropped")
    }

    @Test
    func localEmptyAppliesRemote() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let remoteID = UUID()
        let remote = envelopeData(device: "device-b", checklists: [
            remoteChecklist(id: remoteID, name: "from cloud"),
        ])
        let sync = InMemoryChecklistSync(stored: remote)
        let service = makeService(sync: sync, store: store)

        let outcome = await service.reconcile()

        #expect(outcome == .synced)
        #expect(store.checklists.map(\.id) == [remoteID], "remote-only checklist is absorbed")
        #expect(store.checklists.first?.name == "from cloud")
    }

    @Test
    func descriptionSurvivesMergeAndPush() async throws {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let sync = InMemoryChecklistSync()
        let service = makeService(sync: sync, store: store)
        let item = ChecklistItem(title: "Milk", description: "2 litres")
        let remote = Checklist(name: "Groceries", items: [item])
        sync.stored = try ChecklistCodec.encode(ChecklistEnvelope(deviceID: "device-b", checklists: [remote]))

        let outcome = await service.reconcile()

        #expect(outcome == .synced)
        #expect(store.checklists.first?.items.first?.description == "2 litres")
        let pushed = try #require(sync.stored)
        #expect(ChecklistCodec.decode(pushed).first?.items.first?.description == "2 litres", "the pushed envelope carries the description")
    }

    @Test
    func concurrentTitleAndDescriptionEditsBothSurviveReconcile() async throws {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let checklistID = UUID()
        let itemID = UUID()
        // Local device edited the title last: its title clock is 2/t20, its
        // description clock is the pre-edit baseline.
        let localItem = ChecklistItem(id: itemID, title: "A title", description: "",
            modifiedAt: Date(timeIntervalSince1970: 20), revision: 2,
            titleRevision: 2, titleModifiedAt: Date(timeIntervalSince1970: 20))
        let local = ChecklistEnvelope(deviceID: "device-a", checklists: [
            Checklist(id: checklistID, name: "Groceries", items: [localItem],
                      modifiedAt: Date(timeIntervalSince1970: 10), revision: 1)])
        suite.defaults.set(try ChecklistCodec.encode(local), forKey: "checklists.v1")
        let store = makeStore(defaults: suite.defaults)

        // Remote device edited only the description: its title value is the
        // pre-edit "Milk" and its title clock is the older baseline, so the
        // local title edit wins that axis on clock alone.
        let remoteItem = ChecklistItem(id: itemID, title: "Milk", description: "2 litres",
            modifiedAt: Date(timeIntervalSince1970: 30), revision: 3,
            titleRevision: 1, titleModifiedAt: Date(timeIntervalSince1970: 10),
            descriptionRevision: 3, descriptionModifiedAt: Date(timeIntervalSince1970: 30))
        let sync = InMemoryChecklistSync(stored: envelopeData(device: "device-b", checklists: [
            Checklist(id: checklistID, name: "Groceries", items: [remoteItem],
                      modifiedAt: Date(timeIntervalSince1970: 10), revision: 1)]))
        let service = makeService(sync: sync, store: store)

        let outcome = await service.reconcile()

        #expect(outcome == .synced)
        #expect(store.checklists.first?.items.first?.title == "A title")
        #expect(store.checklists.first?.items.first?.description == "2 litres")
        let pushed = try #require(sync.stored)
        #expect(ChecklistCodec.decode(pushed).first?.items.first?.title == "A title")
        #expect(ChecklistCodec.decode(pushed).first?.items.first?.description == "2 litres")
    }

    @Test
    func bothNonEmptyMergeAndPush() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let local = store.create()
        store.rename(id: local.id, to: "local A")

        let remote = envelopeData(device: "device-b", checklists: [
            remoteChecklist(id: UUID(), name: "remote B"),
        ])
        let sync = InMemoryChecklistSync(stored: remote)
        let service = makeService(sync: sync, store: store)

        let outcome = await service.reconcile()

        #expect(outcome == .synced)
        #expect(store.checklists.map(\.name) == ["local A", "remote B"], "both sides survive the merge")
        #expect(sync.written.count == 1, "the merged payload is pushed once")
    }

    @Test
    func readFailureIsUnavailable() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let sync = InMemoryChecklistSync()
        sync.readError = TestError.boom
        let service = makeService(sync: sync, store: store)

        let outcome = await service.reconcile()

        #expect(outcome == .unavailable)
        #expect(service.lastOutcome == outcome)
    }

    @Test
    func writeFailureIsSurfacedAsFailed() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        _ = store.create()   // non-empty local so the seed path would write
        let sync = InMemoryChecklistSync()
        sync.writeError = TestError.boom
        let service = makeService(sync: sync, store: store)

        let outcome = await service.reconcile()

        #expect(isFailed(outcome))
        #expect(sync.written.isEmpty, "nothing reaches the cloud")
    }

    @Test
    func concurrentRefreshesCoalesceIntoOneRead() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let sync = InMemoryChecklistSync()
        let service = makeService(sync: sync, store: store)

        async let a = service.refresh()
        async let b = service.refresh()
        _ = await (a, b)

        #expect(sync.readCount == 1, "both refreshes share one in-flight reconcile")
    }

    @Test
    func unreadableRemoteIsIgnored() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let local = store.create()
        store.rename(id: local.id, to: "keep me")

        let sync = InMemoryChecklistSync(stored: Data("not json".utf8))
        let service = makeService(sync: sync, store: store)

        let outcome = await service.reconcile()

        #expect(isFailed(outcome))
        #expect(store.checklists.count == 1, "foreign bytes never discard local state")
        #expect(store.checklists.first?.name == "keep me")
        #expect(sync.written.isEmpty, "garbage is not written back")
    }

    @Test
    func observerCallbackTriggersReconcile() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let remoteID = UUID()
        let sync = InMemoryChecklistSync(stored: envelopeData(device: "device-b", checklists: [
            remoteChecklist(id: remoteID, name: "from cloud"),
        ]))
        let service = makeService(sync: sync, store: store)
        service.start()

        sync.fireExternalChange()
        // Give the observer-spawned reconcile task a chance to run.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.checklists.map(\.id) == [remoteID], "external change triggers a reconcile")
    }
}

@MainActor
func isFailed(_ outcome: SyncOutcome) -> Bool {
    if case .failed = outcome { return true }
    return false
}

/// One remote checklist with an explicit id so tests can assert absorption.
@MainActor
func remoteChecklist(id: UUID, name: String) -> Checklist {
    Checklist(id: id, name: name, items: [], modifiedAt: Date(timeIntervalSince1970: 100), revision: 1)
}

/// Encodes an envelope the way the real adapter would store its bytes.
@MainActor
func envelopeData(device: String, checklists: [Checklist] = [], tombstones: [ChecklistTombstone] = []) -> Data {
    (try? ChecklistCodec.encode(ChecklistEnvelope(
        version: ChecklistCodec.currentVersion,
        deviceID: device,
        checklists: checklists,
        tombstones: tombstones))) ?? Data()
}
