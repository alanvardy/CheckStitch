import AppIntents

/// Siri-facing identity for a checklist. `id` is `Checklist.id.uuidString` — the
/// same stable, rename-proof key sync merges on, so a rename never orphans an
/// in-flight utterance.
public struct ChecklistEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Checklist"
    public static var defaultQuery: ChecklistEntityQuery { ChecklistEntityQuery() }

    public let id: String
    public let name: String

    public init(id: String, name: String) { self.id = id; self.name = name }
    public init(_ checklist: Checklist) { self.init(id: checklist.id.uuidString, name: checklist.name) }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

public struct ChecklistEntityQuery: EntityStringQuery {
    private let store: ChecklistStore?

    public init() { self.store = nil }
    public init(store: ChecklistStore) { self.store = store }

    /// Fresh store per call when nothing is injected (design decision 7).
    @MainActor private func currentStore() -> ChecklistStore {
        store ?? ChecklistStore(defaults: AppGroup.defaults)
    }

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [ChecklistEntity] {
        let wanted = Set(identifiers)
        return currentStore().checklists
            .filter { wanted.contains($0.id.uuidString) }
            .map(ChecklistEntity.init)
    }

    @MainActor
    public func entities(matching string: String) async throws -> [ChecklistEntity] {
        currentStore().checklists
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(ChecklistEntity.init)
    }

    @MainActor
    public func suggestedEntities() async throws -> [ChecklistEntity] {
        currentStore().checklists.map(ChecklistEntity.init)
    }
}