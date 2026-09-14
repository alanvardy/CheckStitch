import CheckStitchCore
import Foundation

/// Pure, deterministic merge of two checklist envelopes. The winner rule —
/// higher `revision`, then newer `modifiedAt`, then the lexicographically
/// smaller device id — is symmetric, so both sides compute the same winner
/// regardless of which envelope is `local` and which is `remote`. Tombstones
/// union by `(checklistID, itemID)` and always suppress their live entry, so a
/// deletion made on one device can never be resurrected by an older copy on
/// another. No store, no seam, no I/O: fully unit-testable in isolation.
enum ChecklistMerge {
    static func merge(local: ChecklistEnvelope, remote: ChecklistEnvelope) -> ChecklistEnvelope {
        let tombstones = mergedTombstones(local.tombstones, remote.tombstones)
        let deadChecklists = Set(tombstones.filter { $0.itemID == nil }.map(\.checklistID))
        let itemTombstones = tombstones.filter { $0.itemID != nil }

        var checklists = mergedChecklists(
            local.checklists, remote.checklists,
            localDevice: local.deviceID, remoteDevice: remote.deviceID
        )
        checklists.removeAll { deadChecklists.contains($0.id) }
        for index in checklists.indices {
            let deadItems = Set(
                itemTombstones.filter { $0.checklistID == checklists[index].id }.compactMap(\.itemID)
            )
            checklists[index].items.removeAll { deadItems.contains($0.id) }
            checklists[index].itemOrder.removeAll { deadItems.contains($0) }
        }

        return ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: local.deviceID,
            checklists: checklists,
            tombstones: tombstones
        )
    }

    private struct TombstoneKey: Hashable {
        let checklistID: UUID
        let itemID: UUID?
    }

    private static func mergedTombstones(
        _ local: [ChecklistTombstone], _ remote: [ChecklistTombstone]
    ) -> [ChecklistTombstone] {
        var byKey: [TombstoneKey: ChecklistTombstone] = [:]
        for tombstone in local + remote {
            let key = TombstoneKey(checklistID: tombstone.checklistID, itemID: tombstone.itemID)
            if let existing = byKey[key] {
                if wins(revision: tombstone.revision, date: tombstone.deletedAt,
                        overRevision: existing.revision, overDate: existing.deletedAt) {
                    byKey[key] = tombstone
                }
            } else {
                byKey[key] = tombstone
            }
        }
        // Deterministic order so re-merging an unchanged payload is a no-op.
        return byKey.values.sorted {
            ($0.checklistID.uuidString, $0.itemID?.uuidString ?? "")
                < ($1.checklistID.uuidString, $1.itemID?.uuidString ?? "")
        }
    }

    private static func mergedChecklists(
        _ local: [Checklist], _ remote: [Checklist],
        localDevice: String, remoteDevice: String
    ) -> [Checklist] {
        var result = local
        var indexByID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) })
        for remoteChecklist in remote {
            guard let index = indexByID[remoteChecklist.id] else {
                indexByID[remoteChecklist.id] = result.count
                result.append(remoteChecklist.normalizedOrder())
                continue
            }
            let localChecklist = result[index]
            var merged = localChecklist
            if wins(revision: remoteChecklist.revision, date: remoteChecklist.modifiedAt,
                    device: remoteDevice,
                    overRevision: localChecklist.revision, overDate: localChecklist.modifiedAt,
                    overDevice: localDevice) {
                merged.name = remoteChecklist.name
                merged.revision = remoteChecklist.revision
                merged.modifiedAt = remoteChecklist.modifiedAt
            }

            let mergedItems = mergedItems(
                localChecklist.items, remoteChecklist.items,
                localDevice: localDevice, remoteDevice: remoteDevice
            )
            let remoteWinsOrder = wins(
                revision: remoteChecklist.orderRevision, date: remoteChecklist.orderModifiedAt,
                device: remoteDevice,
                overRevision: localChecklist.orderRevision, overDate: localChecklist.orderModifiedAt,
                overDevice: localDevice
            )
            let winnerOrder = remoteWinsOrder ? remoteChecklist.itemOrder : localChecklist.itemOrder
            let order = reconciledOrder(
                winnerOrder: winnerOrder,
                mergedItems: mergedItems,
                fallback: localChecklist.itemOrder
            )
            merged.items = reorder(mergedItems, to: order)
            merged.itemOrder = order
            if remoteWinsOrder {
                merged.orderRevision = remoteChecklist.orderRevision
                merged.orderModifiedAt = remoteChecklist.orderModifiedAt
            }
            result[index] = merged
        }
        return result
    }

    private static func mergedItems(
        _ local: [ChecklistItem], _ remote: [ChecklistItem],
        localDevice: String, remoteDevice: String
    ) -> [ChecklistItem] {
        var result = local
        var indexByID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) })
        for remoteItem in remote {
            guard let index = indexByID[remoteItem.id] else {
                indexByID[remoteItem.id] = result.count
                result.append(remoteItem)
                continue
            }
            let localItem = result[index]
            if wins(revision: remoteItem.revision, date: remoteItem.modifiedAt, device: remoteDevice,
                    overRevision: localItem.revision, overDate: localItem.modifiedAt, overDevice: localDevice) {
                result[index] = remoteItem
            }
        }
        return result
    }

    /// The merged item id order: winner ids that survive keep winner order; ids
    /// that survive only in the merged list are appended. Deterministic and
    /// symmetric for normalised inputs (each side's `itemOrder` covers its own
    /// items, so the appended sequence is the loser's relative order either way).
    private static func reconciledOrder(
        winnerOrder: [UUID], mergedItems: [ChecklistItem], fallback: [UUID]
    ) -> [UUID] {
        let surviving = Set(mergedItems.map(\.id))
        var order: [UUID] = []
        var seen = Set<UUID>()
        for id in winnerOrder where surviving.contains(id) && seen.insert(id).inserted {
            order.append(id)
        }
        for id in fallback + mergedItems.map(\.id)
        where surviving.contains(id) && seen.insert(id).inserted {
            order.append(id)
        }
        return order
    }

    /// Rebuilds `items` in the reconciled id order. `order` is exactly the set of
    /// merged item ids, so nothing is dropped.
    private static func reorder(_ items: [ChecklistItem], to order: [UUID]) -> [ChecklistItem] {
        // Same defensive build as `Checklist.normalizedOrder()`: never trap on a
        // duplicate id, keep the first occurrence.
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] }
    }

    private static func wins(revision: Int, date: Date, device: String? = nil,
                             overRevision: Int, overDate: Date, overDevice: String? = nil) -> Bool {
        if revision != overRevision { return revision > overRevision }
        if date != overDate { return date > overDate }
        guard let device, let overDevice else { return false }
        return device < overDevice
    }
}
