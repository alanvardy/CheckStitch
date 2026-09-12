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
}