import CheckStitchCore
import Foundation
import Testing

@MainActor
struct UbiquitousChecklistSyncTests {
    @Test
    func realAdapterCanBeConstructed() {
        // Construction canary only: no read/write/synchronize is called, so no
        // KVS API runs in the test host.
        _ = UbiquitousChecklistSync()
    }

    @Test
    func observationCancelIsIdempotent() {
        // Registers/removes a NotificationCenter observer only; no KVS I/O.
        let sync = UbiquitousChecklistSync()
        let token = sync.startObserving {}
        token.cancel()
        token.cancel()
    }

    /// A remote-win `apply` lands the remote `multiple`, so a factor set on one
    /// device survives a subsequent sync merge on another.
    @Test
    func remoteWinApplyCarriesMultiple() throws {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let local = store.create(name: "Groceries")   // revision 1, multiple 1
        let id = local.id

        var remoteChecklist = Checklist(
            id: id, name: "Groceries",
            modifiedAt: Date(timeIntervalSince1970: 100), revision: 2)
        remoteChecklist.multiple = 7
        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "device-b",
            checklists: [remoteChecklist])

        #expect(store.apply(remote: remote), "the remote win changes visible state")
        #expect(store.checklist(id: id)?.multiple == 7, "a remote win carries the remote multiple")
    }
}
