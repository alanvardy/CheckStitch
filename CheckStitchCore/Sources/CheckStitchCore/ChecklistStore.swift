import Foundation
import os

@MainActor @Observable
public final class ChecklistStore {
    /// Whether a `rename(id:to:)` call was applied, refused because another
    /// checklist already owns the requested name, or aimed at an id that no
    /// longer exists (deleted while its screen was visible).
    public enum RenameOutcome: Equatable {
        case renamed
        case nameTaken
        case notFound
    }

    /// Whether a `setDestination(_:for:)` call was applied or aimed at an id that
    /// no longer exists (deleted while its edit screen was visible).
    public enum SetDestinationOutcome: Equatable {
        case updated
        case notFound
    }

    public private(set) var checklists: [Checklist]
    /// Persisted deletion records, unioned by `ChecklistMerge`. There is no
    /// retention/GC yet, so this only grows; it is bounded in practice by human
    /// deletion volume, but a future ticket should compact tombstones once no
    /// device can still hold the pre-delete revision.
    public private(set) var tombstones: [ChecklistTombstone] = []
    /// Persisted folder state, mirroring `checklists`/`tombstones`: unions under
    /// `ChecklistMerge`, loaded through the same envelope, and saved verbatim.
    public private(set) var folders: [Folder] = []
    public private(set) var folderTombstones: [FolderTombstone] = []
    /// Invoked after every persisted save, except saves that are applying remote
    /// state (the coordinator pushes those itself).
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private var isApplyingRemote = false

    private let defaults: UserDefaults
    private let key: String
    /// False when the stored payload came from a newer app version: mutations
    /// still work in memory, but saving is refused so that payload survives.
    private let canOverwriteStoredPayload: Bool
    /// Text fields report every keystroke; their writes are coalesced over this
    /// window. `nil` saves synchronously (used by tests that assert on disk
    /// right after a mutation).
    private let textEditDelay: Duration?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// Stable per-install identifier stamped into every encoded envelope, so a
    /// merge can tell two producers apart (see `ChecklistMerge`).
    public let deviceID: String
    @ObservationIgnored private let now: () -> Date

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = "checklists.v1",
        textEditDelay: Duration? = .milliseconds(300),
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.textEditDelay = textEditDelay
        self.now = now

        if let existing = defaults.string(forKey: Self.deviceIDKey) {
            self.deviceID = existing
        } else {
            let created = UUID().uuidString
            defaults.set(created, forKey: Self.deviceIDKey)
            self.deviceID = created
        }

        if let data = defaults.data(forKey: key) {
            switch ChecklistCodec.classify(data) {
            case .loaded(let stored):
                self.checklists = stored.checklists
                self.tombstones = stored.tombstones
                self.folders = stored.folders
                self.folderTombstones = stored.folderTombstones
                self.canOverwriteStoredPayload = true
            case .migratable(let from, let legacy):
                switch from {
                case 1:
                    // v1 carried no sync state: stamp it (unchanged behaviour).
                    self.checklists = legacy.checklists.map { $0.migrated(at: now()) }
                case 2:
                    // v2 carries sync state but no ordering state: seed ordering
                    // without restamping revision/modifiedAt.
                    self.checklists = legacy.checklists.map { $0.seededOrder() }
                default:
                    // v3+ already carries full sync and ordering state: load it
                    // verbatim so a stored revision/modifiedAt is never restamped.
                    self.checklists = legacy.checklists
                }
                self.tombstones = legacy.tombstones
                self.folders = legacy.folders
                self.folderTombstones = legacy.folderTombstones
                self.canOverwriteStoredPayload = true   // never stall migration
            case .unsupportedVersion:
                self.checklists = []
                self.folders = []
                self.folderTombstones = []
                self.canOverwriteStoredPayload = false
            case .unreadable:
                self.checklists = []
                self.folders = []
                self.folderTombstones = []
                self.canOverwriteStoredPayload = true
            }
        } else {
            self.checklists = []
            self.folders = []
            self.folderTombstones = []
            self.canOverwriteStoredPayload = true
        }
    }

    /// The current payload as a versioned envelope: the only thing the store
    /// ever encodes, keeping "store is the only encoder" literally true.
    public var envelope: ChecklistEnvelope {
        ChecklistEnvelope(version: ChecklistCodec.currentVersion,
                          deviceID: deviceID,
                          checklists: checklists,
                          tombstones: tombstones,
                          folders: folders,
                          folderTombstones: folderTombstones)
    }

    /// Whether remote sync state may be folded into the local payload. False
    /// only when the stored payload came from a newer app version.
    public var canAcceptRemoteChanges: Bool { canOverwriteStoredPayload }

    private static let deviceIDKey = "checklist.deviceID"

    public func checklist(id: UUID) -> Checklist? {
        checklists.first { $0.id == id }
    }

    /// Active (non-archived) checklists. The single source every listing/run/query
    /// surface reads instead of `checklists`.
    public var activeChecklists: [Checklist] { checklists.filter { !$0.isArchived } }

    /// Archived checklists, newest `archivedAt` first; a `nil` date sorts last so
    /// the ordering is total.
    public var archivedChecklists: [Checklist] {
        checklists.filter(\.isArchived).sorted { lhs, rhs in
            switch (lhs.archivedAt, rhs.archivedAt) {
            case let (l?, r?): return l > r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return false
            }
        }
    }

    /// Archives a checklist: sets `isArchived`/`archivedAt` and bumps the coarse
    /// clock. An already-archived or unknown id is a no-op returning `false`.
    @discardableResult
    public func archive(id: UUID) -> Bool {
        guard let index = checklists.firstIndex(where: { $0.id == id }),
              !checklists[index].isArchived else { return false }
        let stampedAt = now()
        checklists[index].isArchived = true
        checklists[index].archivedAt = stampedAt
        checklists[index].revision += 1
        checklists[index].modifiedAt = stampedAt
        save()
        return true
    }

    /// Restores an archived checklist. When its name now collides with an active
    /// checklist the name is disambiguated through `uniqueName`. Unknown or
    /// already-active ids are a no-op returning `false`.
    @discardableResult
    public func restore(id: UUID) -> Bool {
        guard let index = checklists.firstIndex(where: { $0.id == id }),
              checklists[index].isArchived else { return false }
        // `activeNames` lists active checklists only, so the still-archived
        // target is excluded; every occupied name that remains is a live collider
        // driving the disambiguation (e.g. restoring "Groceries" alongside an
        // active "Groceries" yields "Groceries 2").
        if conflictingChecklist(named: checklists[index].name) != nil {
            checklists[index].name = Self.uniqueName(
                basedOn: checklists[index].name,
                taken: activeNames)
        }
        checklists[index].isArchived = false
        checklists[index].archivedAt = nil
        checklists[index].revision += 1
        checklists[index].modifiedAt = now()
        save()
        return true
    }

    /// Names an active checklist currently owns. Archived names are deliberately
    /// free: an active checklist may reuse the name of an archived one.
    private var activeNames: [String] { activeChecklists.map(\.name) }

    /// The first checklist whose name collides with `name` under the store's
    /// trimmed, case-insensitive comparison, or `nil` when the name is free. The
    /// import flow's conflict primitive — `sameName` stays private.
    public func conflictingChecklist(named name: String) -> Checklist? {
        activeChecklists.first { Self.sameName($0.name, name) }
    }

    /// Creates a checklist, disambiguating the name when another checklist
    /// already uses it: `"New checklist"`, `"New checklist 2"`,
    /// `"New checklist 3"`, … Creation therefore always succeeds and returns
    /// the checklist to open.
    @discardableResult
    public func create(name: String = "New checklist") -> Checklist {
        let checklist = Checklist(name: Self.uniqueName(basedOn: name, taken: activeNames), modifiedAt: now(), revision: 1)
        checklists.append(checklist)
        save()
        return checklist
    }

    /// Creates a checklist with a caller-supplied name and one title-only item per
    /// entry, in a single `save()`/single `onChange` — the Create Checklist intent
    /// must not save N times. The name is disambiguated by `uniqueName` exactly as
    /// `create(name:)`. Callers pass a non-blank name and non-blank titles; the
    /// intent normalises and validates before calling.
    @discardableResult
    public func create(name: String, itemTitles: [String]) -> Checklist {
        let items = itemTitles.map { ChecklistItem(title: $0, modifiedAt: now(), revision: 1) }
        let checklist = Checklist(
            name: Self.uniqueName(basedOn: name, taken: activeNames),
            items: items,
            modifiedAt: now(),
            revision: 1)
        checklists.append(checklist)
        save()
        return checklist
    }

    /// The name a duplicate is offered by default: the source name plus a
    /// literal " copy", left for `uniqueName` to disambiguate on commit — a
    /// second copy of "Groceries" is therefore offered as "Groceries copy 2".
    public static func duplicateName(basedOn sourceName: String) -> String {
        "\(sourceName) copy"
    }

    /// Duplicates a checklist: every item is copied into a fresh `ChecklistItem`
    /// (new `UUID`, revision 1), under a name disambiguated by the same
    /// machinery `create` uses, so a duplicate always succeeds. The copy keeps
    /// the source's `destinationListIdentifier`, mirroring `freshCopy`. Returns
    /// `nil` when the source no longer exists, mirroring `delete(id:)`'s silent
    /// no-op. A blank (whitespace- or newline-only) name falls back to the
    /// offered default.
    @discardableResult
    public func duplicate(id: UUID, name: String) -> Checklist? {
        guard let source = checklists.first(where: { $0.id == id }) else { return nil }
        let requested = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.duplicateName(basedOn: source.name)
            : name
        let copy = Checklist(
            name: Self.uniqueName(basedOn: requested, taken: activeNames),
            items: source.items.map { ChecklistItem(title: $0.title, description: $0.description, modifiedAt: now(), revision: 1, relativeDate: $0.relativeDate, priority: $0.priority) },
            destinationListIdentifier: source.destinationListIdentifier,
            prefixesReminderNumbers: source.prefixesReminderNumbers,
            showsOnWatch: source.showsOnWatch,
            multiple: source.multiple,
            modifiedAt: now(),
            revision: 1
        )
        checklists.append(copy)
        save()
        return copy
    }

    /// Fresh local identity for imported content: new checklist AND item UUIDs,
    /// `revision: 1`, stamped now. Mirrors `duplicate`'s semantics. The imported
    /// `destinationListIdentifier` is carried over so the user's chosen Reminders
    /// list survives; if that list is missing on this device the run path's
    /// existing `.destinationMissing` net reports it before creating anything.
    private func freshCopy(of checklist: Checklist) -> Checklist {
        Checklist(
            name: checklist.name,
            items: checklist.items.map {
                ChecklistItem(title: $0.title, description: $0.description,
                              modifiedAt: now(), revision: 1, relativeDate: $0.relativeDate,
                              priority: $0.priority)
            },
            destinationListIdentifier: checklist.destinationListIdentifier,
            prefixesReminderNumbers: checklist.prefixesReminderNumbers,
            showsOnWatch: checklist.showsOnWatch,
            multiple: checklist.multiple,
            isArchived: false,
            archivedAt: nil,
            modifiedAt: now(),
            revision: 1
        )
    }

    /// Inserts imported content as a new local checklist. The name is disambiguated
    /// through `uniqueName` (a no-op for a genuinely free name), which is the
    /// non-destructive "Keep Both" path; pass `name` to force one. Never re-enters
    /// the LWW merge. Returns the new id.
    @discardableResult
    public func importInsert(_ checklist: Checklist, as name: String? = nil) -> UUID {
        var copy = freshCopy(of: checklist)
        copy.name = name ?? Self.uniqueName(basedOn: copy.name, taken: activeNames)
        checklists.append(copy)
        save()
        return copy.id
    }

    /// Replaces an existing checklist with imported content. Records the same
    /// whole-checklist tombstone `delete(id:)` does (`itemID: nil`,
    /// `revision + 1`) but commits delete + insert in a single `save()`, so a
    /// replace is one push. Returns the new id, or `nil` when the local checklist
    /// no longer exists (silent no-op, mirroring `delete`).
    @discardableResult
    public func importReplace(id: UUID, with checklist: Checklist) -> UUID? {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = checklists.remove(at: index)
        tombstones.append(ChecklistTombstone(
            checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
        let copy = freshCopy(of: checklist)
        checklists.append(copy)
        save()
        return copy.id
    }

    /// Renames a checklist and reports whether the name was applied. The
    /// checklist being renamed is excluded from the uniqueness check, so
    /// keeping (or adopting a case/whitespace variant of) its own name is
    /// always allowed. Callers commit this on Done rather than per keystroke,
    /// so the conflict is surfaced once the user confirms the name.
    @discardableResult
    public func rename(id: UUID, to name: String) -> RenameOutcome {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
        guard checklists.first(where: { $0.id != id && !$0.isArchived && Self.sameName($0.name, name) }) == nil else {
            return .nameTaken
        }
        checklists[index].name = name
        checklists[index].revision += 1
        checklists[index].modifiedAt = now()
        scheduleSave()
        return .renamed
    }

    /// Points a checklist at a Reminders list (`nil` = system default) and reports
    /// whether it applied. Follows `rename`: bump revision + `modifiedAt`, then
    /// persist through the coalescing path.
    @discardableResult
    public func setDestination(_ identifier: String?, for id: UUID) -> SetDestinationOutcome {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
        checklists[index].destinationListIdentifier = identifier
        checklists[index].revision += 1
        checklists[index].modifiedAt = now()
        scheduleSave()
        return .updated
    }

    /// Sets a checklist's per-checklist reminder-numbering toggle and reports
    /// whether it applied. Shares the checklist's coarse `revision`/`modifiedAt`
    /// clock with `rename`/`setDestination`, so the toggle rides the same
    /// last-write-wins rule as the name and destination. An unchanged value is a
    /// no-op, so re-rendering the toggle never manufactures a spurious LWW win.
    @discardableResult
    public func setPrefixesReminderNumbers(_ enabled: Bool, for id: UUID) -> SetDestinationOutcome {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
        guard checklists[index].prefixesReminderNumbers != enabled else { return .updated }
        checklists[index].prefixesReminderNumbers = enabled
        checklists[index].revision += 1
        checklists[index].modifiedAt = now()
        scheduleSave()
        return .updated
    }

    /// Sets a checklist's per-checklist "Show on watch" toggle and reports
    /// whether it applied. Shares the checklist's coarse `revision`/`modifiedAt`
    /// clock with `rename`/`setDestination`/`setPrefixesReminderNumbers`, so the
    /// toggle rides the same last-write-wins rule. An unchanged value is a no-op,
    /// so re-rendering the toggle never manufactures a spurious LWW win.
    @discardableResult
    public func setShowsOnWatch(_ enabled: Bool, for id: UUID) -> SetDestinationOutcome {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
        guard checklists[index].showsOnWatch != enabled else { return .updated }
        checklists[index].showsOnWatch = enabled
        checklists[index].revision += 1
        checklists[index].modifiedAt = now()
        scheduleSave()
        return .updated
    }

    /// Sets a checklist's template scaling factor and reports whether it applied.
    /// Clamps into `Checklist.multipleRange` first (defense in depth for
    /// imported/hand-edited payloads), then follows the no-op-guard shape: an
    /// unchanged value never manufactures a spurious LWW win. Shares the
    /// checklist's coarse `revision`/`modifiedAt` clock.
    @discardableResult
    public func setMultiple(_ newValue: Int, for id: UUID) -> SetDestinationOutcome {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
        let clamped = Checklist.clampedMultiple(newValue)
        guard checklists[index].multiple != clamped else { return .updated }
        checklists[index].multiple = clamped
        checklists[index].revision += 1
        checklists[index].modifiedAt = now()
        scheduleSave()
        return .updated
    }

    /// The first free name in the sequence `base`, `base 2`, `base 3`, …, so a
    /// create never collides. `base` is trimmed first, so a typed
    /// `"  Groceries  "` disambiguates as `"Groceries 2"`, not
    /// `"  Groceries   2"`.
    private static func uniqueName(basedOn rawName: String, taken: [String]) -> String {
        let base = rawName.trimmingCharacters(in: CharacterSet.whitespaces)
        guard taken.contains(where: { sameName($0, base) }) else { return base }
        var suffix = 2
        while true {
            let candidate = "\(base) \(suffix)"
            if !taken.contains(where: { sameName($0, candidate) }) { return candidate }
            suffix += 1
        }
    }

    /// Case-insensitive equality on whitespace-trimmed names, so "Groceries",
    /// "groceries" and " groceries " all name the same checklist.
    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: CharacterSet.whitespaces)
            .caseInsensitiveCompare(b.trimmingCharacters(in: CharacterSet.whitespaces)) == .orderedSame
    }

    /// Adds an item to a checklist under the caller-supplied title, creating it
    /// once with that name: a single `revision: 1` create, so the title clock
    /// records add-time. Existing callers without a name to offer keep the
    /// generic default through the `addItem(to:)` overload.
    public func addItem(to id: UUID, title: String) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        let item = ChecklistItem(title: title, modifiedAt: now(), revision: 1)
        checklists[index].items.append(item)
        checklists[index].itemOrder.append(item.id)
        save()
    }

    public func addItem(to id: UUID) {
        addItem(to: id, title: "New item")
    }

    public func updateItem(checklistID: UUID, itemID: UUID, title: String) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        let revisedAt = now()
        checklists[checklistIndex].items[itemIndex].title = title
        checklists[checklistIndex].items[itemIndex].revision += 1
        checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
        checklists[checklistIndex].items[itemIndex].titleRevision = checklists[checklistIndex].items[itemIndex].revision
        checklists[checklistIndex].items[itemIndex].titleModifiedAt = revisedAt
        scheduleSave()
    }

    /// Edits only the item's description, stamping the item's sync identity and
    /// debouncing like `updateItem`. Item ops never touch the checklist's own
    /// `revision`/`modifiedAt` (see `Checklist` doc).
    public func updateItemDescription(checklistID: UUID, itemID: UUID, description: String) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        let revisedAt = now()
        checklists[checklistIndex].items[itemIndex].description = description
        checklists[checklistIndex].items[itemIndex].revision += 1
        checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
        checklists[checklistIndex].items[itemIndex].descriptionRevision = checklists[checklistIndex].items[itemIndex].revision
        checklists[checklistIndex].items[itemIndex].descriptionModifiedAt = revisedAt
        scheduleSave()
    }

    /// Sets (or clears) an item's relative-date offset. Distinct label, so it sits
    /// beside `updateItem(checklistID:itemID:title:)` without ambiguity. An
    /// unchanged value is a no-op — this is what stops a text field re-committing
    /// the same parse from bumping `revision` and winning a spurious LWW round.
    public func updateItem(checklistID: UUID, itemID: UUID, relativeDate: Int?) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        guard checklists[checklistIndex].items[itemIndex].relativeDate != relativeDate else { return }
        let revisedAt = now()
        checklists[checklistIndex].items[itemIndex].relativeDate = relativeDate
        checklists[checklistIndex].items[itemIndex].revision += 1
        checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
        checklists[checklistIndex].items[itemIndex].relativeDateRevision = checklists[checklistIndex].items[itemIndex].revision
        checklists[checklistIndex].items[itemIndex].relativeDateModifiedAt = revisedAt
        scheduleSave()
    }

    /// Sets an item's priority. A discrete pick, so like `relativeDate` an
    /// unchanged value is a no-op (never a spurious LWW win), and the save
    /// debounces like the other field edits.
    public func updateItem(checklistID: UUID, itemID: UUID, priority: ChecklistItemPriority) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        guard checklists[checklistIndex].items[itemIndex].priority != priority else { return }
        let revisedAt = now()
        checklists[checklistIndex].items[itemIndex].priority = priority
        checklists[checklistIndex].items[itemIndex].revision += 1
        checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
        checklists[checklistIndex].items[itemIndex].priorityRevision = checklists[checklistIndex].items[itemIndex].revision
        checklists[checklistIndex].items[itemIndex].priorityModifiedAt = revisedAt
        scheduleSave()
    }

    /// Sets an item's enabled flag. A discrete pick, so like `priority` an
    /// unchanged value is a no-op (never a spurious LWW win), and the save
    /// debounces like the other field edits.
    public func updateItem(checklistID: UUID, itemID: UUID, isEnabled: Bool) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        guard checklists[checklistIndex].items[itemIndex].isEnabled != isEnabled else { return }
        let revisedAt = now()
        checklists[checklistIndex].items[itemIndex].isEnabled = isEnabled
        checklists[checklistIndex].items[itemIndex].revision += 1
        checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
        checklists[checklistIndex].items[itemIndex].enabledRevision = checklists[checklistIndex].items[itemIndex].revision
        checklists[checklistIndex].items[itemIndex].enabledModifiedAt = revisedAt
        scheduleSave()
    }

    public func removeItems(from id: UUID, at offsets: IndexSet) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        for offset in offsets.sorted(by: >) {
            guard checklists[index].items.indices.contains(offset) else { continue }
            let removed = checklists[index].items.remove(at: offset)
            checklists[index].itemOrder.removeAll { $0 == removed.id }
            tombstones.append(ChecklistTombstone(
                checklistID: id, itemID: removed.id, deletedAt: now(), revision: removed.revision + 1))
        }
        save()
    }

    /// Removes whole checklists, one tombstone each. Mirrors
    /// `removeItems(from:at:)`: every removal is stamped in a single batch and
    /// persisted once, so a multi-row removal is one save and one sync push.
    /// Out-of-range offsets are skipped; an all-out-of-range or empty set is a
    /// silent no-op (no tombstone, no save).
    public func removeChecklists(at offsets: IndexSet) {
        let removed = offsets.compactMap { checklists.indices.contains($0) ? checklists[$0] : nil }
        guard !removed.isEmpty else { return }
        for index in offsets.sorted(by: >) where checklists.indices.contains(index) {
            checklists.remove(at: index)
        }
        for checklist in removed {
            tombstones.append(ChecklistTombstone(
                checklistID: checklist.id, itemID: nil, deletedAt: now(),
                revision: checklist.revision + 1))
        }
        save()
    }

    /// Applies SwiftUI's `move(fromOffsets:toOffset:)` index arithmetic: removes
    /// the offsets (descending) and re-inserts them at the destination adjusted
    /// by the number of removed elements that sat before it. Returns `nil` for
    /// any out-of-range input so callers can no-op.
    private static func moved<T>(_ array: [T], from offsets: IndexSet, to destination: Int) -> [T]? {
        guard !offsets.isEmpty else { return nil }
        guard offsets.allSatisfy({ array.indices.contains($0) }) else { return nil }
        guard destination >= 0 && destination <= array.count else { return nil }
        let moving = offsets.sorted().map { array[$0] }
        var result = array
        for offset in offsets.sorted(by: >) { result.remove(at: offset) }
        let insertion = destination - offsets.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: insertion)
        return result
    }

    /// Reorders a checklist's items. A structural edit, so it stamps the
    /// ordering state and persists immediately — item `id`/`title`/`modifiedAt`/
    /// `revision` are untouched, so a pure reorder is never mistaken for an item
    /// edit. Unknown checklist ids and out-of-range offsets/destinations are
    /// silent no-ops.
    public func moveItems(checklistID: UUID, from offsets: IndexSet, to destination: Int) {
        guard let index = checklists.firstIndex(where: { $0.id == checklistID }) else { return }
        guard let items = Self.moved(checklists[index].items, from: offsets, to: destination) else { return }
        checklists[index].items = items
        // Same order, kept in lockstep with the canonical list.
        checklists[index].itemOrder = items.map(\.id)
        checklists[index].orderRevision += 1
        checklists[index].orderModifiedAt = now()
        save()
    }

    /// Reorders checklists. Unlike `moveItems` there is no per-checklist order
    /// clock to stamp: the top-level array order *is* the persisted order, and
    /// `ChecklistMerge` keeps local order (remote-only checklists append), so a
    /// reorder is local-first by design and needs no revision bump.
    /// Out-of-range offsets/destinations are silent no-ops.
    public func moveChecklists(from offsets: IndexSet, to destination: Int) {
        guard let reordered = Self.moved(checklists, from: offsets, to: destination) else { return }
        checklists = reordered
        save()
    }

    /// Creates a folder, disambiguating the name like `create` ("New Folder 2").
    /// Always succeeds; returns the folder so a caller could open/rename it. A
    /// nil or whitespace-only request falls back to "New Folder", so the create
    /// alert can never leave a folder with a blank header.
    @discardableResult
    public func createFolder(name: String? = nil) -> Folder {
        let requested = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(name: Self.uniqueName(basedOn: requested.isEmpty ? "New Folder" : requested, taken: folders.map(\.name)),
                            modifiedAt: now(), revision: 1)
        folders.append(folder)
        save()
        return folder
    }

    /// Files a checklist into `folderID` (`nil` = loose). Bumps the checklist's
    /// coarse revision/`modifiedAt` so the membership wins the LWW round and
    /// transfers through `ChecklistMerge` (no separate clock; mirrors `rename`).
    /// Returns false for an unknown checklist or unknown folder; an unchanged
    /// membership is a no-op (never a spurious LWW win).
    @discardableResult
    public func moveChecklist(id: UUID, toFolder folderID: UUID?) -> Bool {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return false }
        if let folderID, !folders.contains(where: { $0.id == folderID }) { return false }
        guard checklists[index].folderID != folderID else { return true }
        checklists[index].folderID = folderID
        checklists[index].revision += 1
        checklists[index].modifiedAt = now()
        save()
        return true
    }

    /// Renames a folder, disambiguating the requested name against the *other*
    /// folders (so re-confirming a folder's own name is a no-op, never " 2") and
    /// keeping the exact `rename` shape: bump revision + `modifiedAt`, then one save.
    @discardableResult
    public func renameFolder(id: UUID, to name: String) -> Folder? {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return nil }
        // A blank request is a no-op: never blank a folder's header.
        let requested = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else { return folders[index] }
        let disambiguated = Self.uniqueName(basedOn: requested, taken: folders.filter { $0.id != id }.map(\.name))
        guard !Self.sameName(folders[index].name, disambiguated) else { return folders[index] }
        folders[index].name = disambiguated
        folders[index].revision += 1
        folders[index].modifiedAt = now()
        save()
        return folders[index]
    }

    /// Collapses or expands a folder's members on the list screens. Shares the
    /// folder's coarse `revision`/`modifiedAt` clock with the name so the flag
    /// transfers through `ChecklistMerge` (mirrors `renameFolder`); an unchanged
    /// flag is a no-op, never a spurious LWW win. Returns false for an unknown
    /// folder.
    @discardableResult
    public func setFolderCollapsed(id: UUID, _ isCollapsed: Bool) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return false }
        guard folders[index].isCollapsed != isCollapsed else { return true }
        folders[index].isCollapsed = isCollapsed
        folders[index].revision += 1
        folders[index].modifiedAt = now()
        save()
        return true
    }

    /// Reorders folders. Folder order *is* the persisted array order and merge
    /// keeps local order (remote-only appends), so — exactly like
    /// `moveChecklists` — this is local-first and stamps no revision.
    public func moveFolders(from offsets: IndexSet, to destination: Int) {
        guard let reordered = Self.moved(folders, from: offsets, to: destination) else { return }
        folders = reordered
        save()
    }

    /// Deletes a folder: every member is sent back to loose in the same batch
    /// (each member's coarse clock bumps so the orphan wins the LWW round), and
    /// one grow-only `FolderTombstone` blocks resurrection. Never writes
    /// checklist tombstones — the checklists survive.
    public func deleteFolder(id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let removed = folders.remove(at: index)
        let deletedAt = now()
        for checklistIndex in checklists.indices where checklists[checklistIndex].folderID == id {
            checklists[checklistIndex].folderID = nil
            checklists[checklistIndex].revision += 1
            checklists[checklistIndex].modifiedAt = deletedAt
        }
        folderTombstones.append(FolderTombstone(folderID: id, deletedAt: deletedAt, revision: removed.revision + 1))
        save()
    }

    /// Local-only: reminders already created in Reminders are never touched.
    public func delete(id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        let removed = checklists.remove(at: index)
        tombstones.append(ChecklistTombstone(
            checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
        save()
    }

    /// Permanently removes a checklist and tombstones the deletion at
    /// `revision + 1`, so sync can never resurrect it. Intended for the Archived
    /// screen; unknown ids are a no-op returning `false`.
    @discardableResult
    public func removeArchived(id: UUID) -> Bool {
        guard let index = checklists.firstIndex(where: { $0.id == id }),
              checklists[index].isArchived else { return false }
        let removed = checklists.remove(at: index)
        tombstones.append(ChecklistTombstone(
            checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
        save()
        return true
    }

    /// Merges a remote payload into local state. Refuses (no save, no state change)
    /// when the stored payload came from a newer app version, preserving the
    /// never-overwrite-newer guard. Returns whether visible state changed.
    @discardableResult
    public func apply(remote: ChecklistEnvelope) -> Bool {
        guard canOverwriteStoredPayload else { return false }
        // Defensive: the service already rejects non-current versions via
        // `classify`, but a future caller must never merge a foreign shape.
        guard remote.version == ChecklistCodec.currentVersion else { return false }
        var merged = ChecklistMerge.merge(local: envelope, remote: remote)
        // Self-heal after merge: the canonical item list and `itemOrder` must
        // always agree, even when a remote order conflict was folded in.
        merged.checklists = merged.checklists.map { $0.normalizedOrder() }
        guard merged != envelope else { return false }   // idempotent
        let visibleChanged = merged.checklists != checklists
        isApplyingRemote = true
        checklists = merged.checklists
        tombstones = merged.tombstones
        folders = merged.folders
        folderTombstones = merged.folderTombstones
        save()
        isApplyingRemote = false
        return visibleChanged
    }

    /// Re-reads the App Group payload and folds any externally written state
    /// (the Create Checklist intent writes through a fresh store) into memory.
    /// Called on every return to `.active`. Idempotent on a cold launch, where
    /// `init` already read the same payload. `apply(remote:)` suppresses `onChange`;
    /// fire it once explicitly when state actually changed so the iCloud push rides
    /// the change (the watch push rides the SwiftUI `checklists` change).
    @discardableResult
    public func reconcileFromDefaults() -> Bool {
        guard canOverwriteStoredPayload else { return false }
        defaults.synchronize()   // a cross-process App Group write may not be visible yet
        guard let data = defaults.data(forKey: key),
              case .loaded(let remote) = ChecklistCodec.classify(data)
        else { return false }
        let before = envelope
        apply(remote: remote)
        guard envelope != before else { return false }
        onChange?()
        return true
    }

    /// Persists any coalesced text edit immediately. Called when the screen is
    /// dismissed and when the app leaves the foreground, so the debounce window
    /// can never outlive the user's session.
    public func flushPendingSave() {
        guard let pending = pendingSave else { return }
        pendingSave = nil
        pending.cancel()
        save()
    }

    /// Coalesces the per-keystroke writes from text fields; structural edits
    /// keep calling `save()` directly.
    private func scheduleSave() {
        guard let textEditDelay else {
            save()
            return
        }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: textEditDelay)
            guard !Task.isCancelled else { return }
            self.pendingSave = nil
            self.save()
        }
    }

    private func save() {
        // A structural edit persists the whole array, so any queued text-edit
        // save is now redundant and must not land later out of order.
        pendingSave?.cancel()
        pendingSave = nil
        guard canOverwriteStoredPayload else {
            Self.logger.error("Refusing to overwrite checklist payload written by a newer app version")
            return
        }
        do {
            defaults.set(try ChecklistCodec.encode(envelope), forKey: key)
            if !isApplyingRemote { onChange?() }
        } catch {
            Self.logger.error("Failed to save checklists: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistStore")
}