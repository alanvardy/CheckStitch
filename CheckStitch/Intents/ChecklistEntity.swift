import AppIntents
import CheckStitchCore

/// Siri-facing identity for a checklist. `id` is `Checklist.id.uuidString` — the
/// same stable, rename-proof key sync merges on, so a rename never orphans an
/// in-flight utterance.
struct ChecklistEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Checklist"
    static var defaultQuery: ChecklistEntityQuery { ChecklistEntityQuery() }

    let id: String
    let name: String

    init(id: String, name: String) { self.id = id; self.name = name }
    init(_ checklist: Checklist) { self.init(id: checklist.id.uuidString, name: checklist.name) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ChecklistEntityQuery: EntityStringQuery {
    private let store: ChecklistStore?

    init() { self.store = nil }
    init(store: ChecklistStore) { self.store = store }

    /// Fresh store per call when nothing is injected (design decision 7).
    @MainActor private func currentStore() -> ChecklistStore {
        store ?? ChecklistStore(defaults: AppGroup.defaults)
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ChecklistEntity] {
        let wanted = Set(identifiers)
        return currentStore().checklists
            .filter { wanted.contains($0.id.uuidString) }
            .map(ChecklistEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ChecklistEntity] {
        currentStore().checklists
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(ChecklistEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ChecklistEntity] {
        currentStore().checklists.map(ChecklistEntity.init)
    }
}
