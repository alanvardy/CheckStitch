import CheckStitchCore
import Foundation
import os

@Observable
final class ChecklistStore {
    /// Whether a `rename(id:to:)` call was applied, refused because another
    /// checklist already owns the requested name, or aimed at an id that no
    /// longer exists (deleted while its screen was visible).
    enum RenameOutcome: Equatable {
        case renamed
        case nameTaken
        case notFound
    }

    /// Whether a `setDestination(_:for:)` call was applied or aimed at an id that
    /// no longer exists (deleted while its edit screen was visible).
    enum SetDestinationOutcome: Equatable {
        case updated
        case notFound
    }

    private(set) var checklists: [Checklist]
    /// Persisted deletion records, unioned by `ChecklistMerge`. There is no
    /// retention/GC yet, so this only grows; it is bounded in practice by human
    /// deletion volume, but a future ticket should compact tombstones once no
    /// device can still hold the pre-delete revision.
    private(set) var tombstones: [ChecklistTombstone] = []
    /// Invoked after every persisted save, except saves that are applying remote
    /// state (the coordinator pushes those itself).
    @ObservationIgnored var onChange: (() -> Void)?
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
    let deviceID: String
    @ObservationIgnored private let now: () -> Date

    init(
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
                self.canOverwriteStoredPayload = true   // never stall migration
            case .unsupportedVersion:
                self.checklists = []
                self.canOverwriteStoredPayload = false
            case .unreadable:
                self.checklists = []
                self.canOverwriteStoredPayload = true
            }
        } else {
            self.checklists = []
            self.canOverwriteStoredPayload = true
        }
    }

    /// The current payload as a versioned envelope: the only thing the store
    /// ever encodes, keeping "store is the only encoder" literally true.
    var envelope: ChecklistEnvelope {
        ChecklistEnvelope(version: ChecklistCodec.currentVersion,
                          deviceID: deviceID,
                          checklists: checklists,
                          tombstones: tombstones)
    }

    /// Whether remote sync state may be folded into the local payload. False
    /// only when the stored payload came from a newer app version.
    var canAcceptRemoteChanges: Bool { canOverwriteStoredPayload }

    private static let deviceIDKey = "checklist.deviceID"

    func checklist(id: UUID) -> Checklist? {
        checklists.first { $0.id == id }
    }

    /// Creates a checklist, disambiguating the name when another checklist
    /// already uses it: `"New checklist"`, `"New checklist 2"`,
    /// `"New checklist 3"`, … Creation therefore always succeeds and returns
    /// the checklist to open.
    @discardableResult
    func create(name: String = "New checklist") -> Checklist {
        let checklist = Checklist(name: Self.uniqueName(basedOn: name, taken: checklists.map(\.name)), modifiedAt: now(), revision: 1)
        checklists.append(checklist)
        save()
        return checklist
    }

    /// The name a duplicate is offered by default: the source name plus a
    /// literal " copy", left for `uniqueName` to disambiguate on commit — a
    /// second copy of "Groceries" is therefore offered as "Groceries copy 2".
    static func duplicateName(basedOn sourceName: String) -> String {
        "\(sourceName) copy"
    }

    /// Duplicates a checklist: every item is copied into a fresh `ChecklistItem`
    /// (new `UUID`, revision 1), under a name disambiguated by the same
    /// machinery `create` uses, so a duplicate always succeeds. Returns `nil`
    /// when the source no longer exists, mirroring `delete(id:)`'s silent
    /// no-op. A blank (whitespace- or newline-only) name falls back to the
    /// offered default.
    @discardableResult
    func duplicate(id: UUID, name: String) -> Checklist? {
        guard let source = checklists.first(where: { $0.id == id }) else { return nil }
        let requested = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.duplicateName(basedOn: source.name)
            : name
        let copy = Checklist(
            name: Self.uniqueName(basedOn: requested, taken: checklists.map(\.name)),
            items: source.items.map { ChecklistItem(title: $0.title, description: $0.description, modifiedAt: now(), revision: 1, relativeDate: $0.relativeDate) },
            modifiedAt: now(),
            revision: 1
        )
        checklists.append(copy)
        save()
        return copy
    }

    /// Renames a checklist and reports whether the name was applied. The
    /// checklist being renamed is excluded from the uniqueness check, so
    /// keeping (or adopting a case/whitespace variant of) its own name is
    /// always allowed. Callers commit this on Done rather than per keystroke,
    /// so the conflict is surfaced once the user confirms the name.
    @discardableResult
    func rename(id: UUID, to name: String) -> RenameOutcome {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
        guard checklists.first { $0.id != id && Self.sameName($0.name, name) } == nil else {
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
    func setDestination(_ identifier: String?, for id: UUID) -> SetDestinationOutcome {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
        checklists[index].destinationListIdentifier = identifier
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

    func addItem(to id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        let item = ChecklistItem(title: "New item", modifiedAt: now(), revision: 1)
        checklists[index].items.append(item)
        checklists[index].itemOrder.append(item.id)
        save()
    }

    func updateItem(checklistID: UUID, itemID: UUID, title: String) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        checklists[checklistIndex].items[itemIndex].title = title
        checklists[checklistIndex].items[itemIndex].revision += 1
        checklists[checklistIndex].items[itemIndex].modifiedAt = now()
        scheduleSave()
    }

    /// Edits only the item's description, stamping the item's sync identity and
    /// debouncing like `updateItem`. Item ops never touch the checklist's own
    /// `revision`/`modifiedAt` (see `Checklist` doc).
    func updateItemDescription(checklistID: UUID, itemID: UUID, description: String) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        checklists[checklistIndex].items[itemIndex].description = description
        checklists[checklistIndex].items[itemIndex].revision += 1
        checklists[checklistIndex].items[itemIndex].modifiedAt = now()
        scheduleSave()
    }

    /// Sets (or clears) an item's relative-date offset. Distinct label, so it sits
    /// beside `updateItem(checklistID:itemID:title:)` without ambiguity. An
    /// unchanged value is a no-op — this is what stops a text field re-committing
    /// the same parse from bumping `revision` and winning a spurious LWW round.
    func updateItem(checklistID: UUID, itemID: UUID, relativeDate: Int?) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        guard checklists[checklistIndex].items[itemIndex].relativeDate != relativeDate else { return }
        checklists[checklistIndex].items[itemIndex].relativeDate = relativeDate
        checklists[checklistIndex].items[itemIndex].revision += 1
        checklists[checklistIndex].items[itemIndex].modifiedAt = now()
        scheduleSave()
    }

    func removeItems(from id: UUID, at offsets: IndexSet) {
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
    func moveItems(checklistID: UUID, from offsets: IndexSet, to destination: Int) {
        guard let index = checklists.firstIndex(where: { $0.id == checklistID }) else { return }
        guard let items = Self.moved(checklists[index].items, from: offsets, to: destination) else { return }
        checklists[index].items = items
        // Same order, kept in lockstep with the canonical list.
        checklists[index].itemOrder = items.map(\.id)
        checklists[index].orderRevision += 1
        checklists[index].orderModifiedAt = now()
        save()
    }

    /// Local-only: reminders already created in Reminders are never touched.
    func delete(id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        let removed = checklists.remove(at: index)
        tombstones.append(ChecklistTombstone(
            checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
        save()
    }

    /// Merges a remote payload into local state. Refuses (no save, no state change)
    /// when the stored payload came from a newer app version, preserving the
    /// never-overwrite-newer guard. Returns whether visible state changed.
    @discardableResult
    func apply(remote: ChecklistEnvelope) -> Bool {
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
        save()
        isApplyingRemote = false
        return visibleChanged
    }

    /// Persists any coalesced text edit immediately. Called when the screen is
    /// dismissed and when the app leaves the foreground, so the debounce window
    /// can never outlive the user's session.
    func flushPendingSave() {
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
