@testable import CheckStitchCore
import Foundation
import Testing

struct ChecklistSyncDiagnosticsTests {
    @Test(arguments: [
        (SyncGate.watchSend, "watchSend"),
        (SyncGate.watchReceive, "watchReceive"),
        (SyncGate.watchActivation, "watchActivation"),
        (SyncGate.phoneReceive, "phoneReceive"),
        (SyncGate.phoneSend, "phoneSend"),
        (SyncGate.phoneHandle, "phoneHandle"),
        (SyncGate.snapshotLookup, "snapshotLookup"),
        (SyncGate.createOutcome, "createOutcome"),
    ])
    func gateRawValueMatchesWireContract(_ gate: SyncGate, _ raw: String) {
        #expect(gate.rawValue == raw)
    }

    @Test
    func gateCasesAreUniqueAndComplete() {
        #expect(SyncGate.allCases.count == 8)
        #expect(Set(SyncGate.allCases.map(\.rawValue)).count == 8)
    }

    @Test
    func recordFormatsGateWithNoFields() {
        #expect(ChecklistSyncDiagnostics.record(.watchSend) == "[watchSend]")
    }

    @Test
    func recordSortsFieldsByKey() {
        let line = ChecklistSyncDiagnostics.record(.createOutcome, ["count": "2", "alpha": "1"])
        #expect(line == "[createOutcome] alpha=1 count=2")
    }

    @Test
    func recordJoinsFieldsWithSingleSpace() {
        let line = ChecklistSyncDiagnostics.record(.phoneSend, ["a": "1", "b": "2", "c": "3"])
        #expect(line == "[phoneSend] a=1 b=2 c=3")
    }

    @Test
    func shouldResetFileResetsAtAndAboveLimit() {
        let limit: UInt64 = 64 * 1024
        #expect(ChecklistSyncDiagnostics.shouldResetFile(currentSize: limit))
        #expect(ChecklistSyncDiagnostics.shouldResetFile(currentSize: limit + 1))
    }

    @Test
    func shouldResetFileKeepsFileBelowLimit() {
        #expect(!ChecklistSyncDiagnostics.shouldResetFile(currentSize: 0))
        #expect(!ChecklistSyncDiagnostics.shouldResetFile(currentSize: 64 * 1024 - 1))
    }
}