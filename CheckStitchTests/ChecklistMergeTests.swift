@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct ChecklistMergeTests {
    @Test
    func disjointChecklistsAreUnitedLocalOrderFirst() {
        let localID = UUID()
        let remoteID = UUID()
        let local = envelope(device: "device-a", checklists: [
            checklist(id: localID, name: "local", revision: 1),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: remoteID, name: "remoteOnly", revision: 1),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)

        #expect(merged.checklists.map(\.id) == [localID, remoteID], "local first, then remote-only")
        #expect(merged.checklists.map(\.name) == ["local", "remoteOnly"])
    }

    @Test
    func higherRevisionWinsInEitherArgumentOrder() {
        let id = UUID()
        let newer = checklist(id: id, name: "newer", revision: 2, modifiedAt: Date(timeIntervalSince1970: 2))
        let older = checklist(id: id, name: "older", revision: 1, modifiedAt: Date(timeIntervalSince1970: 1))

        let localWins = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [newer]),
            remote: envelope(device: "device-b", checklists: [older])
        )
        let remoteWins = ChecklistMerge.merge(
            local: envelope(device: "device-b", checklists: [older]),
            remote: envelope(device: "device-a", checklists: [newer])
        )

        #expect(localWins.checklists.first?.name == "newer", "local rev 2 wins")
        #expect(remoteWins.checklists.first?.name == "newer", "rev 2 wins even as the remote argument")
    }

    @Test
    func equalRevisionAndTimestampBreakTiesByDeviceID() {
        let id = UUID()
        let sameMoment = Date(timeIntervalSince1970: 1_700_000_000)
        let fromA = checklist(id: id, name: "from-a", revision: 1, modifiedAt: sameMoment)
        let fromB = checklist(id: id, name: "from-b", revision: 1, modifiedAt: sameMoment)

        let aIsLocal = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [fromA]),
            remote: envelope(device: "device-b", checklists: [fromB])
        )
        let aIsRemote = ChecklistMerge.merge(
            local: envelope(device: "device-b", checklists: [fromB]),
            remote: envelope(device: "device-a", checklists: [fromA])
        )

        #expect(aIsLocal.checklists.first?.name == "from-a", "device-a wins when local")
        #expect(aIsRemote.checklists.first?.name == "from-a", "device-a wins when remote")
    }

    @Test
    func tombstonedChecklistIsNeverResurrected() {
        let id = UUID()
        let live = checklist(id: id, name: "live", revision: 5, modifiedAt: Date(timeIntervalSince1970: 100))
        let remote = envelope(device: "device-b", tombstones: [
            tombstone(checklistID: id, revision: 1),
        ])

        let merged = ChecklistMerge.merge(local: envelope(device: "device-a", checklists: [live]), remote: remote)

        #expect(merged.checklists.isEmpty, "a deleted checklist must stay dead")
        #expect(merged.tombstones.map(\.checklistID) == [id], "the tombstone survives the merge")
    }

    @Test
    func tombstonedItemIsRemovedFromLiveChecklist() {
        let checklistID = UUID()
        let doomedItemID = UUID()
        let live = checklist(id: checklistID, name: "live", revision: 1, items: [
            item(id: doomedItemID, title: "doomed", revision: 1),
        ])
        let remote = envelope(device: "device-b", tombstones: [
            tombstone(checklistID: checklistID, itemID: doomedItemID, revision: 2),
        ])

        let merged = ChecklistMerge.merge(local: envelope(device: "device-a", checklists: [live]), remote: remote)

        #expect(merged.checklists.count == 1, "the checklist itself survives")
        #expect(merged.checklists.first?.items.isEmpty == true, "the tombstoned item is dropped")
    }

    @Test
    func itemEditsFromBothDevicesSurvive() {
        let checklistID = UUID()
        let localItemID = UUID()
        let remoteItemID = UUID()
        let local = envelope(device: "device-a", checklists: [
            checklist(id: checklistID, name: "both", revision: 1, items: [
                item(id: localItemID, title: "from local", revision: 1),
            ]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: checklistID, name: "both", revision: 1, items: [
                item(id: remoteItemID, title: "from remote", revision: 1),
            ]),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)

        #expect(merged.checklists.first?.items.count == 2, "distinct item ids both survive")
        #expect(merged.checklists.first?.items.map(\.title) == ["from local", "from remote"])
    }

    @Test
    func sameItemEditedOnBothDevicesUsesLWW() {
        let checklistID = UUID()
        let itemID = UUID()
        let local = envelope(device: "device-a", checklists: [
            checklist(id: checklistID, name: "single", revision: 1, items: [
                item(id: itemID, title: "local edit", revision: 2, modifiedAt: Date(timeIntervalSince1970: 20)),
            ]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: checklistID, name: "single", revision: 1, items: [
                item(id: itemID, title: "remote edit", revision: 1, modifiedAt: Date(timeIntervalSince1970: 10)),
            ]),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)

        #expect(merged.checklists.first?.items.count == 1)
        #expect(merged.checklists.first?.items.first?.title == "local edit", "higher item revision wins")
    }

    @Test
    func identicalEnvelopesAreANoOp() {
        let envelope = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "device-a",
            checklists: [
                checklist(id: UUID(), name: "stable", revision: 1, items: [
                    item(id: UUID(), title: "keep me", revision: 1),
                ]),
            ],
            tombstones: [
                tombstone(checklistID: UUID(), revision: 2),
            ]
        )

        let merged = ChecklistMerge.merge(local: envelope, remote: envelope)

        #expect(merged == envelope, "re-merging an unchanged payload is a no-op")
        #expect(merged.contentEquals(envelope))
    }
}

@MainActor
func envelope(device: String, checklists: [Checklist] = [], tombstones: [ChecklistTombstone] = []) -> ChecklistEnvelope {
    ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: device, checklists: checklists, tombstones: tombstones)
}

@MainActor
func checklist(id: UUID, name: String, revision: Int, modifiedAt: Date = .distantPast, items: [ChecklistItem] = []) -> Checklist {
    Checklist(id: id, name: name, items: items, modifiedAt: modifiedAt, revision: revision)
}

@MainActor
func item(id: UUID, title: String, revision: Int, modifiedAt: Date = .distantPast) -> ChecklistItem {
    ChecklistItem(id: id, title: title, modifiedAt: modifiedAt, revision: revision)
}

@MainActor
func tombstone(checklistID: UUID, itemID: UUID? = nil, revision: Int = 1, deletedAt: Date = .distantPast) -> ChecklistTombstone {
    ChecklistTombstone(checklistID: checklistID, itemID: itemID, deletedAt: deletedAt, revision: revision)
}