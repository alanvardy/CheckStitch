import Foundation
import os

@Observable
final class ChecklistStore {
    private(set) var checklists: [Checklist]

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = AppGroup.defaults, key: String = "checklists.v1") {
        self.defaults = defaults
        self.key = key
        self.checklists = ChecklistStore.load(defaults: defaults, key: key)
    }

    func checklist(id: UUID) -> Checklist? {
        checklists.first { $0.id == id }
    }

    @discardableResult
    func create() -> Checklist {
        let checklist = Checklist()
        checklists.append(checklist)
        save()
        return checklist
    }

    func rename(id: UUID, to name: String) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
        checklists[index].name = name
        save()
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
        save()
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

    private static func load(defaults: UserDefaults, key: String) -> [Checklist] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return ChecklistCodec.decode(data)
    }

    private func save() {
        do {
            defaults.set(try ChecklistCodec.encode(checklists), forKey: key)
        } catch {
            Self.logger.error("Failed to save checklists: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistStore")
}