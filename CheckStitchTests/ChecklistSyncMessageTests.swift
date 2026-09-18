@testable import CheckStitchCore
import Foundation
import Testing

struct ChecklistSyncMessageTests {
    @Test
    func contextRoundTripsThroughUserInfo() {
        let data = Data("hello".utf8)
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.context(data).userInfo) == .context(data))
    }

    @Test
    func runChecklistRoundTripsThroughUserInfo() {
        let id = UUID()
        let runID = UUID()
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.runChecklist(id: id, runID: runID).userInfo)
            == .runChecklist(id: id, runID: runID))
    }

    @Test
    func runChecklistWithoutARunIDIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.runChecklist: UUID().uuidString]) == nil)
    }

    @Test
    func requestChecklistsRoundTripsThroughUserInfo() {
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.requestChecklists.userInfo) == .requestChecklists)
    }

    @Test
    func unknownKeyIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: ["nonsense": true]) == nil)
    }

    @Test
    func wrongValueTypeIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.runChecklist: 42]) == nil)
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.context: "not data"]) == nil)
    }

    @Test
    func runResultRoundTripsThroughUserInfo() {
        let result = RunResult(runID: UUID(), checklistID: UUID(), kind: .created(2))
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.runResult(result).userInfo) == .runResult(result))
    }

    @Test
    func partiallyCreatedRunResultRoundTripsThroughUserInfo() {
        let result = RunResult(runID: UUID(), checklistID: UUID(), kind: .partiallyCreated(created: 2, total: 5))
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.runResult(result).userInfo) == .runResult(result))
    }

    @Test
    func runResultWithAMalformedKindIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: [
            ChecklistSyncKey.runResult: [
                ChecklistSyncKey.runResultRunID: UUID().uuidString,
                ChecklistSyncKey.runResultChecklistID: UUID().uuidString,
                ChecklistSyncKey.runResultKind: "exploded",
            ],
        ]) == nil)
        #expect(ChecklistSyncMessage(userInfo: [
            ChecklistSyncKey.runResult: [
                ChecklistSyncKey.runResultRunID: UUID().uuidString,
                ChecklistSyncKey.runResultChecklistID: UUID().uuidString,
                ChecklistSyncKey.runResultKind: "created", // no count
            ],
        ]) == nil)
        #expect(ChecklistSyncMessage(userInfo: [
            ChecklistSyncKey.runResult: [
                ChecklistSyncKey.runResultRunID: UUID().uuidString,
                ChecklistSyncKey.runResultChecklistID: UUID().uuidString,
                ChecklistSyncKey.runResultKind: "partiallyCreated", // no count or total
            ],
        ]) == nil)
        #expect(ChecklistSyncMessage(userInfo: [
            ChecklistSyncKey.runResult: [
                ChecklistSyncKey.runResultRunID: UUID().uuidString,
                ChecklistSyncKey.runResultChecklistID: UUID().uuidString,
                ChecklistSyncKey.runResultKind: "partiallyCreated",
                ChecklistSyncKey.runResultCount: 2, // count but no total
            ],
        ]) == nil)
    }

    @Test
    func runResultWithANonDictionaryPayloadIsRejected() {
        #expect(ChecklistSyncMessage(userInfo: [ChecklistSyncKey.runResult: "nope"]) == nil)
    }
}