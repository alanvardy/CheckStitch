import Foundation

/// Row the widget renders: one configured checklist, resolved against the store.
public struct ChecklistWidgetRow: Identifiable, Equatable, Sendable {
    public let id: Checklist.ID
    public let name: String
    public let entityID: String        // ChecklistEntity.ID == checklist.id.uuidString
    public let isRunnable: Bool
    public let needsAccess: Bool

    public init(id: Checklist.ID, name: String, entityID: String,
                isRunnable: Bool, needsAccess: Bool) {
        self.id = id
        self.name = name
        self.entityID = entityID
        self.isRunnable = isRunnable
        self.needsAccess = needsAccess
    }
}

public enum ChecklistWidgetAccessState: Equatable, Sendable {
    case ready
    case needsAccess
    case needsPurchase
}

/// Pure mapping from the store's checklists + the widget configuration to the
/// rows the widget renders. No EventKit, no WidgetKit: unit-testable in the gate.
public struct ChecklistWidgetDisplayModel: Equatable, Sendable {
    /// Cap for the multi-row (large) widget; extra configured rows are dropped.
    public static let rowLimit = 6

    public init(checklists: [Checklist], configuration: [ChecklistEntity],
                access: ChecklistWidgetAccessState) {
        let byID = Dictionary(checklists.map { ($0.id.uuidString, $0) },
                              uniquingKeysWith: { first, _ in first })
        self.rows = Array(configuration.prefix(Self.rowLimit).compactMap { entity in
            guard let checklist = byID[entity.id] else { return nil }
            return ChecklistWidgetRow(
                id: checklist.id,
                name: checklist.name,
                entityID: entity.id,
                isRunnable: access == .ready,
                needsAccess: access != .ready)
        })
    }

    public let rows: [ChecklistWidgetRow]
}