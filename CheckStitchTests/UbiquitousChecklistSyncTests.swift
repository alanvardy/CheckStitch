import CheckStitchCore
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
}
