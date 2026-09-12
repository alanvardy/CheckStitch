import CheckStitchCore
import Foundation
import os

@Observable
final class ChecklistStore {
    private(set) var checklists: [Checklist]
    /// The name a rejected `create()`/`rename()` refused because another
    /// checklist already uses it; `nil` while the last mutation was accepted.
    /// The views present an `.alert` while this is set and clear it on
    /// dismissal, so the conflict stays store-owned and view-side code never
    /// re-derives validity.
    var nameConflict: String? = nil

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

    init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = "checklists.v1",
        textEditDelay: Duration? = .milliseconds(300)
    ) {
        self.defaults = defaults
        self.key = key
        self.textEditDelay = textEditDelay

        if let data = defaults.data(forKey: key) {
            switch ChecklistCodec.classify(data) {
            case .loaded(let stored):
                self.checklists = stored
                self.canOverwriteStoredPayload = true
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

    func checklist(id: UUID) -> Checklist? {
        checklists.first { $0.id == id }
    }

    @discardableResult
    func create(name: String = "New checklist") -> Checklist? {
        guard checklists.first { Self.sameName($0.name, name) } == nil else {
            nameConflict = name
            return nil
        }
        nameConflict = nil
        let checklist = Checklist(name: name)
        checklists.append(checklist)
        save()
        return checklist
    }

    func rename(id: UUID, to name: String) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        // The checklist being renamed is excluded, so keeping (or adopting a
        // case/whitespace variant of) its own name is always allowed.
        guard checklists.first { $0.id != id && Self.sameName($0.name, name) } == nil else {
            nameConflict = name
            return
        }
        nameConflict = nil
        checklists[index].name = name
        scheduleSave()
    }

    /// Case-insensitive equality on whitespace-trimmed names, so "Groceries",
    /// "groceries" and " groceries " all name the same checklist.
    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: CharacterSet.whitespaces)
            .caseInsensitiveCompare(b.trimmingCharacters(in: CharacterSet.whitespaces)) == .orderedSame
    }

    func addItem(to id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        checklists[index].items.append(ChecklistItem(title: "New item"))
        save()
    }

    func updateItem(checklistID: UUID, itemID: UUID, title: String) {
        guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
              let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
        else { return }
        checklists[checklistIndex].items[itemIndex].title = title
        scheduleSave()
    }

    func removeItems(from id: UUID, at offsets: IndexSet) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        for offset in offsets.sorted(by: >) {
            guard checklists[index].items.indices.contains(offset) else { continue }
            checklists[index].items.remove(at: offset)
        }
        save()
    }

    /// Local-only: reminders already created in Reminders are never touched.
    func delete(id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        checklists.remove(at: index)
        save()
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
            defaults.set(try ChecklistCodec.encode(checklists), forKey: key)
        } catch {
            Self.logger.error("Failed to save checklists: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistStore")
}