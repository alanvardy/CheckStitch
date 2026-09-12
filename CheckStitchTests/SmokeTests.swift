@testable import CheckStitchCore
import Testing

/// Proves the app-hosted macOS unit target executes, discovers Swift Testing
/// suites, and links CheckStitchCore. Kept after Phase 2 as a permanent canary.
struct SmokeTests {
    @Test
    func harnessRuns() {
        #expect(Bool(true), "Swift Testing harness executes")
    }
}
