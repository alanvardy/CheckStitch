@testable import CheckStitchCore
@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct ChecklistSyncingContractTests {
    @Test
    func writeThenReadRoundTrips() throws {
        let sync = InMemoryChecklistSync()
        let payload = Data("payload".utf8)
        try sync.write(payload)
        #expect(try sync.read() == payload)
    }

    @Test
    func readReturnsNilWhenEmpty() throws {
        #expect(try InMemoryChecklistSync().read() == nil)
    }

    @Test
    func cancelObservationIsIdempotent() {
        let token = InMemoryChecklistSync().startObserving {}
        token.cancel()
        token.cancel()
    }
}