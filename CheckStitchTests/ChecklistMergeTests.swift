@testable import CheckStitch
import CheckStitchCore
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
    func titleAndDescriptionEditsOnDifferentDevicesBothSurvive() {
        let checklistID = UUID()
        let itemID = UUID()
        // Device A edited the title last (coarse revision 2); its description
        // clock is the older baseline. Device B edited the description last
        // (coarse revision 1); its title clock is the older baseline.
        let fromA = item(id: itemID, title: "A title", description: "old note",
                         revision: 2, modifiedAt: Date(timeIntervalSince1970: 20),
                         titleRevision: 2, titleModifiedAt: Date(timeIntervalSince1970: 20),
                         descriptionRevision: 1, descriptionModifiedAt: Date(timeIntervalSince1970: 10))
        let fromB = item(id: itemID, title: "Milk", description: "B note",
                         revision: 1, modifiedAt: Date(timeIntervalSince1970: 10),
                         titleRevision: 1, titleModifiedAt: Date(timeIntervalSince1970: 10),
                         descriptionRevision: 2, descriptionModifiedAt: Date(timeIntervalSince1970: 30))
        let local = envelope(device: "device-a", checklists: [
            checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromA]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromB]),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)
        let mergedItem = merged.checklists.first?.items.first

        #expect(mergedItem?.title == "A title", "the newer title clock wins")
        #expect(mergedItem?.description == "B note", "the newer description clock wins")
        #expect(mergedItem?.revision == 2, "the whole-item winner's coarse clock survives")
        #expect(mergedItem?.modifiedAt == Date(timeIntervalSince1970: 20))
        // The winner's per-field clocks are copied verbatim, not re-seeded.
        #expect(mergedItem?.titleRevision == 2)
        #expect(mergedItem?.titleModifiedAt == Date(timeIntervalSince1970: 20))
        #expect(mergedItem?.descriptionRevision == 2)
        #expect(mergedItem?.descriptionModifiedAt == Date(timeIntervalSince1970: 30))
        // The loser's values still win their own axes on re-merge: replaying the
        // merged result (and the original remote) is a contentEquals no-op.
        #expect(ChecklistMerge.merge(local: merged, remote: merged).contentEquals(merged))
        #expect(ChecklistMerge.merge(local: merged, remote: remote).contentEquals(merged))
    }

    @Test
    func titleAndDescriptionEditsOnDifferentDevicesBothSurviveReversed() {
        let checklistID = UUID()
        let itemID = UUID()
        let fromA = item(id: itemID, title: "A title", description: "old note",
                         revision: 2, modifiedAt: Date(timeIntervalSince1970: 20),
                         titleRevision: 2, titleModifiedAt: Date(timeIntervalSince1970: 20),
                         descriptionRevision: 1, descriptionModifiedAt: Date(timeIntervalSince1970: 10))
        let fromB = item(id: itemID, title: "Milk", description: "B note",
                         revision: 1, modifiedAt: Date(timeIntervalSince1970: 10),
                         titleRevision: 1, titleModifiedAt: Date(timeIntervalSince1970: 10),
                         descriptionRevision: 2, descriptionModifiedAt: Date(timeIntervalSince1970: 30))
        let aFirst = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromA])]),
            remote: envelope(device: "device-b", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromB])]))
        let bFirst = ChecklistMerge.merge(
            local: envelope(device: "device-b", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromB])]),
            remote: envelope(device: "device-a", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromA])]))

        #expect(aFirst.checklists == bFirst.checklists, "the per-field merge is argument-order independent")
        #expect(bFirst.checklists.first?.items.first?.title == "A title")
        #expect(bFirst.checklists.first?.items.first?.description == "B note")
    }

    @Test
    func relativeDateAndTitleEditsOnDifferentDevicesBothSurvive() {
        let checklistID = UUID()
        let itemID = UUID()
        // Device A changed the relative date last (coarse revision 2); its
        // title clock is the older baseline. Device B edited the title last
        // (coarse revision 1); its relative-date clock is the older baseline.
        // Both sides share the untouched description baseline (1/t10), so the
        // description axis is deterministic too.
        let fromA = item(id: itemID, title: "Milk", revision: 2, modifiedAt: Date(timeIntervalSince1970: 20),
                         relativeDate: 3,
                         titleRevision: 1, titleModifiedAt: Date(timeIntervalSince1970: 10),
                         descriptionRevision: 1, descriptionModifiedAt: Date(timeIntervalSince1970: 10),
                         relativeDateRevision: 2, relativeDateModifiedAt: Date(timeIntervalSince1970: 20))
        let fromB = item(id: itemID, title: "B title", revision: 1, modifiedAt: Date(timeIntervalSince1970: 10),
                         titleRevision: 2, titleModifiedAt: Date(timeIntervalSince1970: 30),
                         descriptionRevision: 1, descriptionModifiedAt: Date(timeIntervalSince1970: 10),
                         relativeDateRevision: 1, relativeDateModifiedAt: Date(timeIntervalSince1970: 10))
        let local = envelope(device: "device-a", checklists: [
            checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromA]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromB]),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)
        let mergedItem = merged.checklists.first?.items.first

        #expect(mergedItem?.title == "B title", "the newer title clock wins")
        #expect(mergedItem?.relativeDate == 3, "the newer relative-date clock wins")
        #expect(mergedItem?.revision == 2, "the whole-item winner's coarse clock survives")
        #expect(mergedItem?.modifiedAt == Date(timeIntervalSince1970: 20))
        // The winner's per-field clocks are copied verbatim, not re-seeded.
        #expect(mergedItem?.titleRevision == 2)
        #expect(mergedItem?.titleModifiedAt == Date(timeIntervalSince1970: 30))
        #expect(mergedItem?.relativeDateRevision == 2)
        #expect(mergedItem?.relativeDateModifiedAt == Date(timeIntervalSince1970: 20))
        // The loser's values still win their own axes on re-merge: replaying the
        // merged result (and the original remote) is a contentEquals no-op.
        #expect(ChecklistMerge.merge(local: merged, remote: merged).contentEquals(merged))
        #expect(ChecklistMerge.merge(local: merged, remote: remote).contentEquals(merged))
    }

    @Test
    func relativeDateAndTitleEditsOnDifferentDevicesBothSurviveReversed() {
        let checklistID = UUID()
        let itemID = UUID()
        let fromA = item(id: itemID, title: "Milk", revision: 2, modifiedAt: Date(timeIntervalSince1970: 20),
                         relativeDate: 3,
                         titleRevision: 1, titleModifiedAt: Date(timeIntervalSince1970: 10),
                         descriptionRevision: 1, descriptionModifiedAt: Date(timeIntervalSince1970: 10),
                         relativeDateRevision: 2, relativeDateModifiedAt: Date(timeIntervalSince1970: 20))
        let fromB = item(id: itemID, title: "B title", revision: 1, modifiedAt: Date(timeIntervalSince1970: 10),
                         titleRevision: 2, titleModifiedAt: Date(timeIntervalSince1970: 30),
                         descriptionRevision: 1, descriptionModifiedAt: Date(timeIntervalSince1970: 10),
                         relativeDateRevision: 1, relativeDateModifiedAt: Date(timeIntervalSince1970: 10))
        let aFirst = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromA])]),
            remote: envelope(device: "device-b", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromB])]))
        let bFirst = ChecklistMerge.merge(
            local: envelope(device: "device-b", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromB])]),
            remote: envelope(device: "device-a", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromA])]))

        #expect(aFirst.checklists == bFirst.checklists, "the per-field merge is argument-order independent")
        #expect(bFirst.checklists.first?.items.first?.title == "B title")
        #expect(bFirst.checklists.first?.items.first?.relativeDate == 3)
    }

    @Test
    func sameFieldEditsStillResolveByFieldLWW() {
        let checklistID = UUID()
        let itemID = UUID()
        let local = envelope(device: "device-a", checklists: [
            checklist(id: checklistID, name: "single", revision: 1, items: [
                item(id: itemID, title: "local edit", revision: 2, modifiedAt: Date(timeIntervalSince1970: 20),
                     titleRevision: 2, titleModifiedAt: Date(timeIntervalSince1970: 20)),
            ]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: checklistID, name: "single", revision: 1, items: [
                item(id: itemID, title: "remote edit", revision: 1, modifiedAt: Date(timeIntervalSince1970: 10),
                     titleRevision: 1, titleModifiedAt: Date(timeIntervalSince1970: 10)),
            ]),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)

        #expect(merged.checklists.first?.items.count == 1)
        #expect(merged.checklists.first?.items.first?.title == "local edit", "the higher titleRevision wins")
        #expect(merged.checklists.first?.items.first?.revision == 2, "the winner's coarse clock is kept")
    }

    @Test
    func tombstoneBeatsANewerFieldClock() {
        let checklistID = UUID()
        let mayBeDeleted = UUID()
        let local = envelope(device: "device-a", checklists: [
            checklist(id: checklistID, name: "live", revision: 1, items: [
                item(id: mayBeDeleted, title: "from a", revision: 5, modifiedAt: Date(timeIntervalSince1970: 500),
                     titleRevision: 5, titleModifiedAt: Date(timeIntervalSince1970: 500)),
            ]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: checklistID, name: "live", revision: 1, items: [
                item(id: mayBeDeleted, title: "from b", revision: 4, modifiedAt: Date(timeIntervalSince1970: 400),
                     descriptionRevision: 4, descriptionModifiedAt: Date(timeIntervalSince1970: 400)),
            ]),
        ], tombstones: [
            tombstone(checklistID: checklistID, itemID: mayBeDeleted, revision: 2),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)

        #expect(merged.checklists.first?.items.isEmpty == true, "a tombstone outlives any field clock")
        #expect(merged.tombstones.map(\.itemID) == [mayBeDeleted], "the tombstone survives the merge")
    }

    @Test
    func legacySeededClocksResolveOneWinningField() {
        let checklistID = UUID()
        let itemID = UUID()
        // A legacy build wrote no field clocks: the plain init seeds every
        // field clock from the coarse clock (5/t50), and the upgraded record's
        // description edit (6/t60) postdates the seeded one while its title
        // clock (3/t30) predates it.
        let legacy = item(id: itemID, title: "Milk", description: "old note",
                          revision: 5, modifiedAt: Date(timeIntervalSince1970: 50))
        let upgraded = item(id: itemID, title: "Milk (typo)", description: "new note",
                            revision: 4, modifiedAt: Date(timeIntervalSince1970: 40),
                            titleRevision: 3, titleModifiedAt: Date(timeIntervalSince1970: 30),
                            descriptionRevision: 6, descriptionModifiedAt: Date(timeIntervalSince1970: 60))
        let local = envelope(device: "device-a", checklists: [
            checklist(id: checklistID, name: "Groceries", revision: 1, items: [legacy]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: checklistID, name: "Groceries", revision: 1, items: [upgraded]),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)
        let mergedItem = merged.checklists.first?.items.first

        #expect(mergedItem?.title == "Milk", "the seeded title clock (5/t50) beats the stale 3/t30 title edit")
        #expect(mergedItem?.description == "new note", "the newer description clock (6/t60) wins its own axis")
        #expect(mergedItem?.revision == 5, "the whole-item winner's coarse clock survives")
        #expect(mergedItem?.titleRevision == 5)
        #expect(mergedItem?.titleModifiedAt == Date(timeIntervalSince1970: 50))
        #expect(mergedItem?.descriptionRevision == 6)
        #expect(mergedItem?.descriptionModifiedAt == Date(timeIntervalSince1970: 60))
        // The losers' axes still win on replay: re-merging with the original
        // remote must be a contentEquals no-op.
        #expect(ChecklistMerge.merge(local: merged, remote: remote).contentEquals(merged))
    }

    @Test
    func emptyDeviceIDsResolvePerFieldDeterministically() {
        let checklistID = UUID()
        let itemID = UUID()
        let sameMoment = Date(timeIntervalSince1970: 1_700_000_000)
        // Both sides carry equal clocks on every axis; only the values differ.
        // With no device id in the tie-break (`"" < ""` is false), no axis may
        // win, so each argument order keeps exactly its own local copy.
        let fromA = item(id: itemID, title: "A title", description: "A note", revision: 1,
                         modifiedAt: sameMoment,
                         titleRevision: 1, titleModifiedAt: sameMoment,
                         descriptionRevision: 1, descriptionModifiedAt: sameMoment,
                         relativeDateRevision: 1, relativeDateModifiedAt: sameMoment)
        let fromB = item(id: itemID, title: "B title", description: "B note", revision: 1,
                         modifiedAt: sameMoment,
                         titleRevision: 1, titleModifiedAt: sameMoment,
                         descriptionRevision: 1, descriptionModifiedAt: sameMoment,
                         relativeDateRevision: 1, relativeDateModifiedAt: sameMoment)
        let local = envelope(device: "", checklists: [
            checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromA]),
        ])
        let remote = envelope(device: "", checklists: [
            checklist(id: checklistID, name: "Groceries", revision: 1, items: [fromB]),
        ])

        let aFirst = ChecklistMerge.merge(local: local, remote: remote)
        let bFirst = ChecklistMerge.merge(local: remote, remote: local)

        // No win without a device id: each order reproduces its local input
        // exactly, so the merge never spuriously reassigns a field.
        #expect(aFirst.checklists == local.checklists)
        #expect(bFirst.checklists == remote.checklists)
        #expect(aFirst.checklists.first?.items.first?.title == "A title")
        #expect(aFirst.checklists.first?.items.first?.description == "A note")
        #expect(bFirst.checklists.first?.items.first?.title == "B title")
        #expect(bFirst.checklists.first?.items.first?.description == "B note")
        #expect(aFirst.tombstones == bFirst.tombstones)
    }

    @Test
    func distinctItemDescriptionsBothSurvive() {
        let checklistID = UUID()
        let a = item(id: UUID(), title: "Milk", description: "a note", revision: 1)
        let b = item(id: UUID(), title: "Eggs", description: "b note", revision: 1)
        let merged = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [a])]),
            remote: envelope(device: "device-b", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [b])]))
        let descriptions: [String] = merged.checklists.first?.items.map(\.description) ?? []
        #expect(Set(descriptions) == Set(["a note", "b note"]), "both devices' descriptions survive the merge")
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

    @Test
    func orderWinnerIsHigherOrderRevision() {
        let id = UUID()
        let a = UUID()
        let b = UUID()
        let items = [
            item(id: a, title: "a", revision: 1),
            item(id: b, title: "b", revision: 1),
        ]
        let ordered = checklist(id: id, name: "same", revision: 1,
            itemOrder: [a, b], orderRevision: 1, items: items)
        let reordered = checklist(id: id, name: "same", revision: 1,
            itemOrder: [b, a], orderRevision: 2, items: items)

        let remoteWins = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [ordered]),
            remote: envelope(device: "device-b", checklists: [reordered])
        )
        let localWins = ChecklistMerge.merge(
            local: envelope(device: "device-b", checklists: [reordered]),
            remote: envelope(device: "device-a", checklists: [ordered])
        )

        #expect(remoteWins.checklists.first?.itemOrder == [b, a], "higher orderRevision wins as the remote argument")
        #expect(localWins.checklists.first?.itemOrder == [b, a], "higher orderRevision wins as the local argument")
        #expect(remoteWins.checklists.first?.items.map(\.id) == [b, a], "items follow the reconciled order")
        #expect(localWins.checklists.first?.items.map(\.id) == [b, a])
    }

    @Test
    func orderTieBreaksByTimestampThenDevice() {
        let id = UUID()
        let a = UUID()
        let b = UUID()
        let items = [
            item(id: a, title: "a", revision: 1),
            item(id: b, title: "b", revision: 1),
        ]
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_100)
        let abOld = checklist(id: id, name: "same", revision: 1,
            itemOrder: [a, b], orderRevision: 1, orderModifiedAt: older, items: items)
        let baNew = checklist(id: id, name: "same", revision: 1,
            itemOrder: [b, a], orderRevision: 1, orderModifiedAt: newer, items: items)

        let newerRemote = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [abOld]),
            remote: envelope(device: "device-b", checklists: [baNew])
        )
        let newerLocal = ChecklistMerge.merge(
            local: envelope(device: "device-b", checklists: [baNew]),
            remote: envelope(device: "device-a", checklists: [abOld])
        )
        #expect(newerRemote.checklists.first?.itemOrder == [b, a], "newer orderModifiedAt wins when remote")
        #expect(newerLocal.checklists.first?.itemOrder == [b, a], "newer orderModifiedAt wins when local")

        let abSame = checklist(id: id, name: "same", revision: 1,
            itemOrder: [a, b], orderRevision: 1, orderModifiedAt: older, items: items)
        let baSame = checklist(id: id, name: "same", revision: 1,
            itemOrder: [b, a], orderRevision: 1, orderModifiedAt: older, items: items)
        let aLocal = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [abSame]),
            remote: envelope(device: "device-b", checklists: [baSame])
        )
        let aRemote = ChecklistMerge.merge(
            local: envelope(device: "device-b", checklists: [baSame]),
            remote: envelope(device: "device-a", checklists: [abSame])
        )
        #expect(aLocal.checklists.first?.itemOrder == [a, b], "device-a wins when local on an order tie")
        #expect(aRemote.checklists.first?.itemOrder == [a, b], "device-a wins when remote on an order tie")
    }

    @Test
    func remoteOnlyItemIsAppendedInWinnerOrder() {
        let id = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let local = envelope(device: "device-a", checklists: [
            checklist(id: id, name: "same", revision: 1,
                itemOrder: [a, b], orderRevision: 1, items: [
                    item(id: a, title: "a", revision: 1),
                    item(id: b, title: "b", revision: 1),
                ]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: id, name: "same", revision: 1,
                itemOrder: [b, a], orderRevision: 2, items: [
                    item(id: a, title: "a", revision: 1),
                    item(id: b, title: "b", revision: 1),
                    item(id: c, title: "c", revision: 1),
                ]),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)

        #expect(merged.checklists.first?.itemOrder == [b, a, c], "the remote-only id is appended after the winner's ids")
        #expect(merged.checklists.first?.items.map(\.id) == [b, a, c])
    }

    @Test
    func remoteOnlyItemIsAppendedWhenOrderWinnerIsLocal() {
        let id = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let local = envelope(device: "device-a", checklists: [
            checklist(id: id, name: "same", revision: 1,
                itemOrder: [b, a], orderRevision: 2, items: [
                    item(id: a, title: "a", revision: 1),
                    item(id: b, title: "b", revision: 1),
                ]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: id, name: "same", revision: 1,
                itemOrder: [a, b], orderRevision: 1, items: [
                    item(id: a, title: "a", revision: 1),
                    item(id: b, title: "b", revision: 1),
                    item(id: c, title: "c", revision: 1),
                ]),
        ])

        let merged = ChecklistMerge.merge(local: local, remote: remote)

        #expect(merged.checklists.first?.itemOrder == [b, a, c], "the remote-only id is appended when the local order wins")
        #expect(merged.checklists.first?.items.map(\.id) == [b, a, c])
    }

    @Test
    func tombstonedItemIsExcludedFromMergedOrder() {
        let checklistID = UUID()
        let a = UUID()
        let b = UUID()
        let live = envelope(device: "device-a", checklists: [
            checklist(id: checklistID, name: "live", revision: 1,
                itemOrder: [a, b], orderRevision: 2, items: [
                    item(id: a, title: "a", revision: 1),
                    item(id: b, title: "b", revision: 1),
                ]),
        ])
        let remote = envelope(device: "device-b", tombstones: [
            tombstone(checklistID: checklistID, itemID: a, revision: 2),
        ])

        let merged = ChecklistMerge.merge(local: live, remote: remote)

        #expect(merged.checklists.first?.items.map(\.id) == [b], "the tombstoned item is dropped from items")
        #expect(merged.checklists.first?.itemOrder == [b], "the tombstoned id is dropped from itemOrder")
    }

    @Test
    func orderReconciliationIsSymmetric() {
        let id = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let shared = item(id: a, title: "shared", revision: 1)
        let fromA = checklist(id: id, name: "from-a", revision: 5, modifiedAt: Date(timeIntervalSince1970: 50),
            itemOrder: [a, b], orderRevision: 4, orderModifiedAt: Date(timeIntervalSince1970: 40),
            items: [shared, item(id: b, title: "b", revision: 1)])
        let fromB = checklist(id: id, name: "from-b", revision: 4, modifiedAt: Date(timeIntervalSince1970: 40),
            itemOrder: [c, a], orderRevision: 3, orderModifiedAt: Date(timeIntervalSince1970: 30),
            items: [shared, item(id: c, title: "c", revision: 1)])

        let localFirst = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [fromA]),
            remote: envelope(device: "device-b", checklists: [fromB])
        )
        let remoteFirst = ChecklistMerge.merge(
            local: envelope(device: "device-b", checklists: [fromB]),
            remote: envelope(device: "device-a", checklists: [fromA])
        )

        #expect(localFirst.checklists == remoteFirst.checklists, "the merged checklists are argument-order independent")
        #expect(localFirst.checklists.first?.itemOrder == [a, b, c])
        #expect(remoteFirst.checklists.first?.itemOrder == [a, b, c])
    }

    @Test
    func orderReconciliationIsIdempotent() {
        let id = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let shared = item(id: a, title: "shared", revision: 1)
        let local = envelope(device: "device-a", checklists: [
            checklist(id: id, name: "from-a", revision: 5, modifiedAt: Date(timeIntervalSince1970: 50),
                itemOrder: [a, b], orderRevision: 4, orderModifiedAt: Date(timeIntervalSince1970: 40),
                items: [shared, item(id: b, title: "b", revision: 1)]),
        ])
        let remote = envelope(device: "device-b", checklists: [
            checklist(id: id, name: "from-b", revision: 4, modifiedAt: Date(timeIntervalSince1970: 40),
                itemOrder: [c, a], orderRevision: 3, orderModifiedAt: Date(timeIntervalSince1970: 30),
                items: [shared, item(id: c, title: "c", revision: 1)]),
        ])

        let once = ChecklistMerge.merge(local: local, remote: remote)
        let mergedAgain = ChecklistMerge.merge(local: once, remote: once)
        let replayRemote = ChecklistMerge.merge(local: once, remote: remote)

        #expect(mergedAgain.checklists == once.checklists, "re-merging an unchanged envelope is a no-op")
        #expect(replayRemote.checklists == once.checklists, "replaying the original remote does not change the merge")
        #expect(once.checklists.first?.itemOrder == [a, b, c])
    }

    @Test
    func winnerDestinationOverwritesLoser() {
        let id = UUID()
        let newer = checklist(id: id, name: "newer", revision: 2, modifiedAt: Date(timeIntervalSince1970: 2), destination: "list-b")
        let older = checklist(id: id, name: "older", revision: 1, modifiedAt: Date(timeIntervalSince1970: 1), destination: "list-a")

        let merged = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [older]),
            remote: envelope(device: "device-b", checklists: [newer])
        )

        #expect(merged.checklists.first?.destinationListIdentifier == "list-b", "the newest editor controls the destination")
    }

    @Test
    func loserDestinationIsPreservedWhenNonWinning() {
        let id = UUID()
        let newer = checklist(id: id, name: "newer", revision: 2, modifiedAt: Date(timeIntervalSince1970: 2), destination: "list-b")
        let older = checklist(id: id, name: "older", revision: 1, modifiedAt: Date(timeIntervalSince1970: 1), destination: "list-a")

        let merged = ChecklistMerge.merge(
            local: envelope(device: "device-a", checklists: [newer]),
            remote: envelope(device: "device-b", checklists: [older])
        )

        #expect(merged.checklists.first?.destinationListIdentifier == "list-b", "an older revision must not leak its destination in")
    }
}

@MainActor
func envelope(device: String, checklists: [Checklist] = [], tombstones: [ChecklistTombstone] = []) -> ChecklistEnvelope {
    ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: device, checklists: checklists, tombstones: tombstones)
}

@MainActor
func checklist(id: UUID, name: String, revision: Int, modifiedAt: Date = .distantPast,
    itemOrder: [UUID]? = nil, orderRevision: Int = 0, orderModifiedAt: Date = .distantPast,
    items: [ChecklistItem] = [], destination: String? = nil) -> Checklist {
    Checklist(id: id, name: name, items: items, destinationListIdentifier: destination,
              modifiedAt: modifiedAt, revision: revision,
              itemOrder: itemOrder, orderRevision: orderRevision, orderModifiedAt: orderModifiedAt)
}

@MainActor
func item(id: UUID, title: String, description: String = "", revision: Int,
          modifiedAt: Date = .distantPast, relativeDate: Int? = nil,
          titleRevision: Int? = nil, titleModifiedAt: Date? = nil,
          descriptionRevision: Int? = nil, descriptionModifiedAt: Date? = nil,
          relativeDateRevision: Int? = nil, relativeDateModifiedAt: Date? = nil) -> ChecklistItem {
    ChecklistItem(id: id, title: title, description: description, modifiedAt: modifiedAt,
                  revision: revision, relativeDate: relativeDate,
                  titleRevision: titleRevision, titleModifiedAt: titleModifiedAt,
                  descriptionRevision: descriptionRevision, descriptionModifiedAt: descriptionModifiedAt,
                  relativeDateRevision: relativeDateRevision, relativeDateModifiedAt: relativeDateModifiedAt)
}

@MainActor
func tombstone(checklistID: UUID, itemID: UUID? = nil, revision: Int = 1, deletedAt: Date = .distantPast) -> ChecklistTombstone {
    ChecklistTombstone(checklistID: checklistID, itemID: itemID, deletedAt: deletedAt, revision: revision)
}
