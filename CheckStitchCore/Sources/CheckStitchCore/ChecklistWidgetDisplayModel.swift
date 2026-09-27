import Foundation

/// Row the widget renders: one configured checklist, resolved against the store.
public struct ChecklistWidgetRow: Identifiable, Equatable, Sendable {
    public let id: Checklist.ID
    public let name: String
    public let entityID: String        // ChecklistEntity.ID == checklist.id.uuidString
    public let isRunnable: Bool
    /// True for any non-`.ready` state: the row opens the app on tap.
    public let needsAccess: Bool
    /// True only when the free-run limit was reached without a license, so the
    /// views can offer "buy a license" instead of the access prompt.
    public let needsPurchase: Bool
    /// The run button's icon: play, a spinner while a run is in flight, or the
    /// transient success check. Always `.play` for a non-runnable row.
    public let indicator: WidgetRunIndicator

    public init(id: Checklist.ID, name: String, entityID: String,
                isRunnable: Bool, needsAccess: Bool, needsPurchase: Bool,
                indicator: WidgetRunIndicator = .play) {
        self.id = id
        self.name = name
        self.entityID = entityID
        self.isRunnable = isRunnable
        self.needsAccess = needsAccess
        self.needsPurchase = needsPurchase
        self.indicator = indicator
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
                access: ChecklistWidgetAccessState,
                runIndicators: [Checklist.ID: WidgetRunIndicator] = [:]) {
        let byID = Dictionary(checklists.map { ($0.id.uuidString, $0) },
                              uniquingKeysWith: { first, _ in first })
        self.rows = Array(configuration.prefix(Self.rowLimit).compactMap { entity in
            guard let checklist = byID[entity.id] else { return nil }
            return ChecklistWidgetRow(
                id: checklist.id,
                name: checklist.name,
                entityID: entity.id,
                isRunnable: access == .ready,
                needsAccess: access != .ready,
                needsPurchase: access == .needsPurchase,
                indicator: runIndicators[checklist.id] ?? .play)
        })
        self.hasChecklists = !checklists.isEmpty
    }

    public let rows: [ChecklistWidgetRow]

    /// Whether the store has any checklist at all, letting the empty-state hint
    /// distinguish "nothing configured yet" from "nothing to configure".
    public let hasChecklists: Bool
}