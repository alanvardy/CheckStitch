import Foundation
import os

/// Editable row model for a checklist item. The ID is stable so rows can be
/// added, removed, and edited without conflating duplicate titles. `modifiedAt`
/// and `revision` carry the sync identity the merge compares; both are
/// optional on decode so v1 payloads (which carried no sync state) still load.
public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    public init(
        id: UUID = UUID(), title: String, description: String = "",
        modifiedAt: Date = .distantPast, revision: Int = 0, relativeDate: Int? = nil,
        priority: ChecklistItemPriority = .none,
        titleRevision: Int? = nil, titleModifiedAt: Date? = nil,
        descriptionRevision: Int? = nil, descriptionModifiedAt: Date? = nil,
        relativeDateRevision: Int? = nil, relativeDateModifiedAt: Date? = nil,
        priorityRevision: Int? = nil, priorityModifiedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.modifiedAt = modifiedAt
        self.revision = revision
        self.relativeDate = relativeDate
        // A fresh record (or a legacy payload) attributes its last whole-item edit
        // to every field, so a nil field clock seeds from the coarse clock.
        self.titleRevision = titleRevision ?? revision
        self.titleModifiedAt = titleModifiedAt ?? modifiedAt
        self.descriptionRevision = descriptionRevision ?? revision
        self.descriptionModifiedAt = descriptionModifiedAt ?? modifiedAt
        self.relativeDateRevision = relativeDateRevision ?? revision
        self.relativeDateModifiedAt = relativeDateModifiedAt ?? modifiedAt
        self.priority = priority
        self.priorityRevision = priorityRevision ?? revision
        self.priorityModifiedAt = priorityModifiedAt ?? modifiedAt
    }

    public let id: UUID
    public var title: String
    public var description: String
    public var modifiedAt: Date
    public var revision: Int
    /// Days from today (0 = today, 1 = tomorrow, negative = past); `nil` = no date.
    /// No time-of-day support. Not clamped — the arithmetic in
    /// `ChecklistItem+DueDate.swift` is the only consumer.
    public var relativeDate: Int?
    /// Per-field sync identity: each editable field carries its own clock so a
    /// title edit and a description edit from two devices are independent.
    public var titleRevision: Int
    public var titleModifiedAt: Date
    public var descriptionRevision: Int
    public var descriptionModifiedAt: Date
    public var relativeDateRevision: Int
    public var relativeDateModifiedAt: Date
    /// The user's priority pick. Its raw value is `EKReminder.priority`'s scale
    /// (0/9/5/1), so writing a created reminder needs no switch.
    public var priority: ChecklistItemPriority
    public var priorityRevision: Int
    public var priorityModifiedAt: Date

    /// True when the item carries description text. The stored value is
    /// preserved verbatim (matching `title`), so surrounding whitespace on real
    /// text is kept; a whitespace-only value reads as "no description", so it
    /// neither renders on the watch nor reaches reminder notes. Consumed by the
    /// watch row and the reminder-notes normalisation.
    public var hasDescription: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A title that is empty or whitespace/newlines only. Creation skips these
    /// so an emptied row can't produce a meaningless reminder.
    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, modifiedAt, revision, relativeDate
        case titleRevision, titleModifiedAt, descriptionRevision, descriptionModifiedAt
        case relativeDateRevision, relativeDateModifiedAt
        case priority, priorityRevision, priorityModifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        // Additive optional field: absent key decodes to "", matching the
        // destinationListIdentifier precedent — no version bump.
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        // Absent in v2-and-earlier payloads and in `nil`-valued current payloads.
        relativeDate = try container.decodeIfPresent(Int.self, forKey: .relativeDate)
        // Additive optional keys: absent in pre-upgrade payloads, so seed each field
        // clock from the item's coarse clock (today's semantics on first contact).
        titleRevision = try container.decodeIfPresent(Int.self, forKey: .titleRevision) ?? revision
        titleModifiedAt = try container.decodeIfPresent(Date.self, forKey: .titleModifiedAt) ?? modifiedAt
        descriptionRevision = try container.decodeIfPresent(Int.self, forKey: .descriptionRevision) ?? revision
        descriptionModifiedAt = try container.decodeIfPresent(Date.self, forKey: .descriptionModifiedAt) ?? modifiedAt
        relativeDateRevision = try container.decodeIfPresent(Int.self, forKey: .relativeDateRevision) ?? revision
        relativeDateModifiedAt = try container.decodeIfPresent(Date.self, forKey: .relativeDateModifiedAt) ?? modifiedAt
        // Additive key: absence decodes to `.none` with no version bump (the
        // `relativeDate` precedent). Unlike `relativeDate` (`Int?`, any value),
        // this enum is a closed domain — an unknown raw value throws, so adding
        // a case later requires a v5 envelope bump (→ `.unsupportedVersion`,
        // which refuses to overwrite) rather than riding this key.
        priority = try container.decodeIfPresent(ChecklistItemPriority.self, forKey: .priority) ?? .none
        priorityRevision = try container.decodeIfPresent(Int.self, forKey: .priorityRevision) ?? revision
        priorityModifiedAt = try container.decodeIfPresent(Date.self, forKey: .priorityModifiedAt) ?? modifiedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(revision, forKey: .revision)
        // Write the key unconditionally, matching the "encoder writes every key"
        // invariant. `encode` on an `Int?` may omit the key depending on overload
        // resolution, so be explicit.
        if let relativeDate {
            try container.encode(relativeDate, forKey: .relativeDate)
        } else {
            try container.encodeNil(forKey: .relativeDate)
        }
        try container.encode(titleRevision, forKey: .titleRevision)
        try container.encode(titleModifiedAt, forKey: .titleModifiedAt)
        try container.encode(descriptionRevision, forKey: .descriptionRevision)
        try container.encode(descriptionModifiedAt, forKey: .descriptionModifiedAt)
        try container.encode(relativeDateRevision, forKey: .relativeDateRevision)
        try container.encode(relativeDateModifiedAt, forKey: .relativeDateModifiedAt)
        try container.encode(priority, forKey: .priority)
        try container.encode(priorityRevision, forKey: .priorityRevision)
        try container.encode(priorityModifiedAt, forKey: .priorityModifiedAt)
    }
}

/// A named collection of items that can be turned into reminders.
///
/// `modifiedAt`/`revision` describe the checklist record itself, not its items:
/// a rename or a destination change bumps them (`ChecklistStore.addItem`/
/// `updateItem`/`removeItems` do not), so checklist-level last-write-wins
/// decides the name and destination while items merge independently on their
/// own `modifiedAt`/`revision`.
public struct Checklist: Identifiable, Codable, Hashable, Sendable {
    public init(
        id: UUID = UUID(), name: String = "New checklist", items: [ChecklistItem] = [],
        destinationListIdentifier: String? = nil,
        prefixesReminderNumbers: Bool = false,
        folderID: UUID? = nil,
        modifiedAt: Date = .distantPast, revision: Int = 0,
        itemOrder: [UUID]? = nil, orderRevision: Int = 0, orderModifiedAt: Date = .distantPast
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.destinationListIdentifier = destinationListIdentifier
        self.prefixesReminderNumbers = prefixesReminderNumbers
        self.folderID = folderID
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
    /// `EKCalendar.calendarIdentifier` of the chosen Reminders list. `nil` means
    /// "system default list", so legacy payloads keep today's behaviour.
    public var destinationListIdentifier: String?
    /// Whether this checklist's created reminder titles get a 1-based prefix.
    /// Per-checklist so two checklists can differ; it shares the checklist's
    /// coarse `revision`/`modifiedAt` clock (like the name and destination), so
    /// a toggle is decided by the same last-write-wins rule. Additive optional
    /// key: absent in v4-and-earlier payloads decodes to `false` with no version
    /// bump (the `relativeDate` precedent).
    public var prefixesReminderNumbers: Bool
    /// The id of the folder this checklist is filed under, or `nil` for loose.
    /// A one-field relationship sharing the checklist's coarse clock with the
    /// name/destination, so a membership move is decided by the same
    /// last-write-wins rule. `nil` is encoded, never dropped.
    public var folderID: UUID?
    public var modifiedAt: Date
    public var revision: Int
    /// Canonical item ordering as a list of item ids. Kept in lockstep with
    /// `items` (see `normalizedOrder()`); stamped independently of item
    /// `revision`/`modifiedAt` so a reorder is never mistaken for an item edit.
    public var itemOrder: [UUID]
    public var orderRevision: Int
    public var orderModifiedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, items, destinationListIdentifier, prefixesReminderNumbers, folderID
        case modifiedAt, revision, itemOrder, orderRevision, orderModifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let items = try container.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
        let destinationListIdentifier = try container.decodeIfPresent(String.self, forKey: .destinationListIdentifier)
        // Additive optional field: absent key decodes to false, matching the
        // `description`/`relativeDate` precedent — no version bump.
        let prefixesReminderNumbers = try container.decodeIfPresent(Bool.self, forKey: .prefixesReminderNumbers) ?? false
        // Additive optional field: absent in v4-and-earlier payloads decodes to
        // nil, matching the `destinationListIdentifier` precedent — no restamp.
        let folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        let modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        let revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        let itemOrder = try container.decodeIfPresent([UUID].self, forKey: .itemOrder) ?? items.map(\.id)
        let orderRevision = try container.decodeIfPresent(Int.self, forKey: .orderRevision) ?? 0
        let orderModifiedAt = try container.decodeIfPresent(Date.self, forKey: .orderModifiedAt) ?? .distantPast
        // Decode-time self-heal: a payload whose `itemOrder` disagrees with `items`
        // (or omits an id) is canonicalised rather than trusted. Built through
        // the public init so the whole value is assigned at once.
        self = Checklist(id: id, name: name, items: items,
                         destinationListIdentifier: destinationListIdentifier,
                         prefixesReminderNumbers: prefixesReminderNumbers,
                         folderID: folderID,
                         modifiedAt: modifiedAt, revision: revision,
                         itemOrder: itemOrder, orderRevision: orderRevision, orderModifiedAt: orderModifiedAt)
            .normalizedOrder()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        try container.encode(destinationListIdentifier, forKey: .destinationListIdentifier)
        try container.encode(prefixesReminderNumbers, forKey: .prefixesReminderNumbers)
        // Write the key unconditionally, matching the "encoder writes every key"
        // invariant (the `relativeDate` shape).
        if let folderID {
            try container.encode(folderID, forKey: .folderID)
        } else {
            try container.encodeNil(forKey: .folderID)
        }
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(itemOrder, forKey: .itemOrder)
        try container.encode(orderRevision, forKey: .orderRevision)
        try container.encode(orderModifiedAt, forKey: .orderModifiedAt)
    }
}

extension Checklist {
    /// Upgrades a v1 entry: v1 carried no sync or ordering state, so stamp both
    /// from the record's own identity rather than granting a spurious win.
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
            upgraded.titleRevision = upgraded.revision
            upgraded.titleModifiedAt = date
            upgraded.descriptionRevision = upgraded.revision
            upgraded.descriptionModifiedAt = date
            upgraded.relativeDateRevision = upgraded.revision
            upgraded.relativeDateModifiedAt = date
            upgraded.priorityRevision = upgraded.revision
            upgraded.priorityModifiedAt = date
            return upgraded
        }
        return copy
    }

    /// Upgrades a v2 entry's ordering: v2 carried item/checklist sync state but
    /// no ordering state, so seed `orderRevision`/`orderModifiedAt` from the
    /// record's own sync state. Unlike `migrated(at:)`, this never restamps the
    /// item or checklist `revision`/`modifiedAt` — v2 already has real sync
    /// identity, and restamping it would manufacture spurious LWW wins.
    public func seededOrder() -> Checklist {
        var copy = self
        copy.orderRevision = max(revision, 1)
        copy.orderModifiedAt = modifiedAt
        if copy.itemOrder.isEmpty {
            copy.itemOrder = copy.items.map(\.id)
        }
        return copy
    }

    /// Canonicalises `items` to `itemOrder` and appends any item id missing
    /// from it, so the encoded array order and the explicit order never
    /// diverge. Idempotent; used on decode, after merge, and after any
    /// mutation that touches `items`.
    public func normalizedOrder() -> Checklist {
        var copy = self
        // `uniquingKeysWith` keeps this total on hand-corrupted payloads: decode
        // must never trap, and duplicate ids are deduped by `seen` below anyway.
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

/// A named group that checklists can be filed under. `revision`/`modifiedAt`
/// carry the same last-write-wins identity `Checklist` uses, so folder renames
/// and deletes converge through `ChecklistMerge`.
public struct Folder: Identifiable, Codable, Hashable, Sendable {
    public init(id: UUID = UUID(), name: String = "New Folder",
                modifiedAt: Date = .distantPast, revision: Int = 0) {
        self.id = id
        self.name = name
        self.modifiedAt = modifiedAt
        self.revision = revision
    }

    public let id: UUID
    public var name: String
    public var modifiedAt: Date
    public var revision: Int
}

/// A persisted folder-deletion record. Mirrors `ChecklistTombstone`: it only
/// grows, and suppresses its live folder under `ChecklistMerge`.
public struct FolderTombstone: Codable, Hashable, Sendable {
    public init(folderID: UUID, deletedAt: Date, revision: Int) {
        self.folderID = folderID
        self.deletedAt = deletedAt
        self.revision = revision
    }

    public let folderID: UUID
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
    public var folders: [Folder]
    public var folderTombstones: [FolderTombstone]

    public init(version: Int = ChecklistCodec.currentVersion,
         deviceID: String,
         checklists: [Checklist],
         tombstones: [ChecklistTombstone] = [],
         folders: [Folder] = [],
         folderTombstones: [FolderTombstone] = []) {
        self.version = version
        self.deviceID = deviceID
        self.checklists = checklists
        self.tombstones = tombstones
        self.folders = folders
        self.folderTombstones = folderTombstones
    }

    private enum CodingKeys: String, CodingKey { case version, deviceID, checklists, tombstones, folders, folderTombstones }

    // v1 payloads have neither deviceID nor tombstones.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        checklists = try container.decodeIfPresent([Checklist].self, forKey: .checklists) ?? []
        tombstones = try container.decodeIfPresent([ChecklistTombstone].self, forKey: .tombstones) ?? []
        // v4-and-earlier payloads have no folder keys: decode to empty the way
        // `tombstones` does, so a folderless legacy payload loads verbatim.
        folders = try container.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        folderTombstones = try container.decodeIfPresent([FolderTombstone].self, forKey: .folderTombstones) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(checklists, forKey: .checklists)
        try container.encode(tombstones, forKey: .tombstones)
        try container.encode(folders, forKey: .folders)
        try container.encode(folderTombstones, forKey: .folderTombstones)
    }
}

extension ChecklistEnvelope {
    /// Envelope equality ignoring the producer's device id — used to decide
    /// whether a reconciled result must be pushed back to the cloud.
    public func contentEquals(_ other: ChecklistEnvelope) -> Bool {
        version == other.version && checklists == other.checklists && tombstones == other.tombstones
            && folders == other.folders && folderTombstones == other.folderTombstones
    }
}

public enum ChecklistCodec {
    public static let currentVersion = 5

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistCodec")

    /// How a stored payload relates to the version this build understands. The
    /// store needs the distinction so it can decline to overwrite data written
    /// by a newer app sharing the App Group suite.
    public enum Outcome: Equatable {
        case loaded(ChecklistEnvelope)
        /// A known older version that can be upgraded in place. Carries the
        /// whole envelope so a legacy payload keeps its `deviceID`, tombstones,
        /// and any sync state the loaders must not restamp.
        case migratable(from: Int, envelope: ChecklistEnvelope)
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
            case 4:
                // v4 carries full sync and ordering state, but predates folders. Load
                // verbatim, never restamp; absent folder keys decode to []/nil.
                let previous = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
                return .migratable(from: 4, envelope: previous)
            case 3:
                // v3 carries full sync and ordering state: load it verbatim,
                // never restamp. It predates `relativeDate`, which decodes nil.
                let previous = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
                return .migratable(from: 3, envelope: previous)
            case 2:
                // v2 carries sync state but no ordering state; the loaders seed
                // ordering without restamping. Load verbatim here.
                let previous = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
                return .migratable(from: 2, envelope: previous)
            case 1:
                let legacy = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
                return .migratable(from: 1, envelope: legacy)
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
        case .migratable(_, let envelope): return envelope.checklists
        case .unsupportedVersion, .unreadable: return []
        }
    }

    private struct VersionProbe: Decodable { let version: Int }
}

/// One rendered group on the list screens. `folder == nil` is the loose group.
public struct ChecklistSection: Identifiable, Equatable, Sendable {
    public init(folder: Folder?, checklists: [Checklist]) {
        self.folder = folder
        self.checklists = checklists
    }

    public let folder: Folder?
    public let checklists: [Checklist]
    public var id: String { folder?.id.uuidString ?? "loose" }
    public var name: String? { folder?.name }
}

/// Read-only grouping used by the watch (and any surface that needs sections).
public enum ChecklistGrouping {
    /// Folders in persisted order, each followed by its members in global
    /// checklist order; then the loose section last. A `folderID` naming an
    /// unknown folder is grouped loose, so cross-reference skew never drops a
    /// checklist.
    public static func sections(folders: [Folder], checklists: [Checklist]) -> [ChecklistSection] {
        let known = Set(folders.map(\.id))
        var byFolder: [UUID: [Checklist]] = [:]
        var loose: [Checklist] = []
        for checklist in checklists {
            if let folderID = checklist.folderID, known.contains(folderID) {
                byFolder[folderID, default: []].append(checklist)
            } else {
                loose.append(checklist)
            }
        }
        var sections = folders.map { ChecklistSection(folder: $0, checklists: byFolder[$0.id] ?? []) }
        sections.append(ChecklistSection(folder: nil, checklists: loose))
        return sections
    }
}
