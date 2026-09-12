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
        #expect(ChecklistSyncMessage(userInfo: ChecklistSyncMessage.runChecklist(id).userInfo) == .runChecklist(id))
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
}