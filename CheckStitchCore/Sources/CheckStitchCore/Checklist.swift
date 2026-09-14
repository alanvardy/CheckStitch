import Foundation
import os

/// Editable row model for a checklist item. The ID is stable so rows can be
/// added, removed, and edited without conflating duplicate titles. `modifiedAt`
/// and `revision` carry the sync identity the merge compares; both are
/// optional on decode so v1 payloads (which carried no sync state) still load.
public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    public init(id: UUID = UUID(), title: String, modifiedAt: Date = .distantPast, revision: Int = 0) {
        self.id = id
        self.title = title
        self.modifiedAt = modifiedAt
        self.revision = revision
    }

    public let id: UUID
    public var title: String
    public var modifiedAt: Date
    public var revision: Int

    /// A title that is empty or whitespace/newlines only. Creation skips these
    /// so an emptied row can't produce a meaningless reminder.
    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey { case id, title, modifiedAt, revision }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(revision, forKey: .revision)
    }
}

/// A named collection of items that can be turned into reminders.
///
/// `modifiedAt`/`revision` describe the checklist record itself, not its items:
/// only a rename bumps them (`ChecklistStore.addItem`/`updateItem`/
/// `removeItems` do not), so checklist-level last-write-wins decides the name
/// while items merge independently on their own `modifiedAt`/`revision`.
public struct Checklist: Identifiable, Codable, Hashable, Sendable {
    public init(
        id: UUID = UUID(), name: String = "New checklist", items: [ChecklistItem] = [],
        modifiedAt: Date = .distantPast, revision: Int = 0,
        itemOrder: [UUID]? = nil, orderRevision: Int = 0, orderModifiedAt: Date = .distantPast
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.modifiedAt = modifiedAt
        self.revision = revision
        // Canonical order defaults to the array's own order; an explicit value is
        // honoured so drift can be constructed/observed by tests.
        self.itemOrder = itemOrder ?? items.map(\.id)
        self.orderRevision = orderRevision
        self.orderModifiedAt = orderModifiedAt
    }

    public let id: UUID
    public var name: String
    public var items: [ChecklistItem]
    public var modifiedAt: Date
    public var revision: Int
    /// Canonical item ordering as a list of item ids. Kept in lockstep with
    /// `items` (see `normalizedOrder()`); stamped independently of item
    /// `revision`/`modifiedAt` so a reorder is never mistaken for an item edit.
    public var itemOrder: [UUID]
    public var orderRevision: Int
    public var orderModifiedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, items, modifiedAt, revision, itemOrder, orderRevision, orderModifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let items = try container.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
        let modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        let revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        let itemOrder = try container.decodeIfPresent([UUID].self, forKey: .itemOrder) ?? items.map(\.id)
        let orderRevision = try container.decodeIfPresent(Int.self, forKey: .orderRevision) ?? 0
        let orderModifiedAt = try container.decodeIfPresent(Date.self, forKey: .orderModifiedAt) ?? .distantPast
        // Decode-time self-heal: a payload whose `itemOrder` disagrees with `items`
        // (or omits an id) is canonicalised rather than trusted. Built through
        // the public init so the whole value is assigned at once.
        self = Checklist(id: id, name: name, items: items, modifiedAt: modifiedAt, revision: revision,
                         itemOrder: itemOrder, orderRevision: orderRevision, orderModifiedAt: orderModifiedAt)
            .normalizedOrder()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(itemOrder, forKey: .itemOrder)
        try container.encode(orderRevision, forKey: .orderRevision)
        try container.encode(orderModifiedAt, forKey: .orderModifiedAt)
    }
}

extension Checklist {
    /// Upgrades a pre-v3 entry: v1/v2 carried no ordering state, so seed it from
    /// the record's own sync state rather than granting a spurious ordering win.
    public func migrated(at date: Date) -> Checklist {
        var copy = self
        let priorModifiedAt = modifiedAt
        copy.modifiedAt = date
        copy.revision = max(revision, 1)
        // Pre-v3 payloads carry no ordering; seed it from the record's own
        // revision/date so migration grants no spurious ordering win.
        copy.orderRevision = max(revision, 1)
        copy.orderModifiedAt = priorModifiedAt
        if copy.itemOrder.isEmpty {
            copy.itemOrder = copy.items.map(\.id)
        }
        copy.items = copy.items.map { item in
            var upgraded = item
            upgraded.modifiedAt = date
            upgraded.revision = max(upgraded.revision, 1)
            return upgraded
        }
        return copy
    }

    /// Canonicalises `items` to `itemOrder` and appends any item id missing
    /// from it, so the encoded array order and the explicit order never
    /// diverge. Idempotent; used on decode, after merge, and after any
    /// mutation that touches `items`.
    func normalizedOrder() -> Checklist {
        var copy = self
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var order: [UUID] = []
        var seen = Set<UUID>()
        for id in itemOrder where byID[id] != nil && seen.insert(id).inserted {
            order.append(id)
        }
        for item in items where seen.insert(item.id).inserted {
            order.append(item.id)
        }
        copy.itemOrder = order
        copy.items = order.compactMap { byID[$0] }
        return copy
    }
}

/// A persisted deletion record. `itemID` distinguishes a whole-checklist
/// deletion (`nil`) from a single item's, so a delete made on one device can
/// never be resurrected by an older copy on another.
public struct ChecklistTombstone: Codable, Hashable, Sendable {
    public init(checklistID: UUID, itemID: UUID?, deletedAt: Date, revision: Int) {
        self.checklistID = checklistID
        self.itemID = itemID
        self.deletedAt = deletedAt
        self.revision = revision
    }

    public let checklistID: UUID
    public let itemID: UUID?
    public var deletedAt: Date
    public var revision: Int
}

/// Versioned wire format for the App Group payload. The version field exists so
/// VAR-963 can evolve decoding instead of silently mis-reading old data.
public struct ChecklistEnvelope: Codable, Sendable, Equatable {
    public var version: Int
    public var deviceID: String
    public var checklists: [Checklist]
    public var tombstones: [ChecklistTombstone]

    public init(version: Int = ChecklistCodec.currentVersion,
         deviceID: String,
         checklists: [Checklist],
         tombstones: [ChecklistTombstone] = []) {
        self.version = version
        self.deviceID = deviceID
        self.checklists = checklists
        self.tombstones = tombstones
    }

    private enum CodingKeys: String, CodingKey { case version, deviceID, checklists, tombstones }

    // v1 payloads have neither deviceID nor tombstones.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        checklists = try container.decodeIfPresent([Checklist].self, forKey: .checklists) ?? []
        tombstones = try container.decodeIfPresent([ChecklistTombstone].self, forKey: .tombstones) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(checklists, forKey: .checklists)
        try container.encode(tombstones, forKey: .tombstones)
    }
}

extension ChecklistEnvelope {
    /// Envelope equality ignoring the producer's device id — used to decide
    /// whether a reconciled result must be pushed back to the cloud.
    public func contentEquals(_ other: ChecklistEnvelope) -> Bool {
        version == other.version && checklists == other.checklists && tombstones == other.tombstones
    }
}

public enum ChecklistCodec {
    public static let currentVersion = 3

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistCodec")

    /// How a stored payload relates to the version this build understands. The
    /// store needs the distinction so it can decline to overwrite data written
    /// by a newer app sharing the App Group suite.
    public enum Outcome: Equatable {
        case loaded(ChecklistEnvelope)
        /// A known older version that can be upgraded in place.
        case migratable(from: Int, checklists: [Checklist])
        /// Written by a future version whose shape is unknown.
        case unsupportedVersion
        /// Garbage that cannot be decoded. Callers choose the response: the
        /// store replaces it, while the sync service refuses to write over
        /// remote bytes it could not understand.
        case unreadable
    }

    public static func encode(_ envelope: ChecklistEnvelope) throws -> Data {
        try JSONEncoder().encode(envelope)
    }

    /// Classifies a payload — never a crash, never a partial decode. Probes the
    /// version before decoding the rest so a future version is never mis-read.
    public static func classify(_ data: Data) -> Outcome {
        do {
            let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
            switch probe.version {
            case currentVersion:
                return .loaded(try JSONDecoder().decode(ChecklistEnvelope.self, from: data))
            case 1, 2:
                let legacy = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
                return .migratable(from: probe.version, checklists: legacy.checklists)
            default:
                logger.error("Unsupported checklist payload version \(probe.version, privacy: .public); treating as empty")
                return .unsupportedVersion
            }
        } catch {
            logger.error("Failed to decode checklist payload: \(error.localizedDescription, privacy: .public)")
            return .unreadable
        }
    }

    /// Convenience for readers that only need the values.
    public static func decode(_ data: Data) -> [Checklist] {
        switch classify(data) {
        case .loaded(let envelope): return envelope.checklists
        case .migratable(_, let checklists): return checklists
        case .unsupportedVersion, .unreadable: return []
        }
    }

    private struct VersionProbe: Decodable { let version: Int }
}
