import AppIntents

/// Siri/Shortcuts identity for a Reminders list. `"default"` is the synthetic
/// system-default choice; every other id is `EKCalendar.calendarIdentifier`.
public struct ReminderListEntity: AppEntity {
    public static let defaultID = "default"
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Reminder List"
    public static var defaultQuery: ReminderListEntityQuery { ReminderListEntityQuery() }

    public let id: String
    public let name: String

    public init(id: String, name: String) { self.id = id; self.name = name }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

public struct ReminderListEntityQuery: EntityQuery {
    private let targeting: (any ReminderDestinationTargeting)?

    public init() { self.targeting = nil }
    public init(targeting: any ReminderDestinationTargeting) { self.targeting = targeting }

    @MainActor
    private func currentTargeting() -> any ReminderDestinationTargeting {
        targeting ?? EventKitReminderDestination.shared
    }

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [ReminderListEntity] {
        let all = await allEntities()
        let wanted = Set(identifiers)
        return all.filter { wanted.contains($0.id) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [ReminderListEntity] {
        await allEntities()
    }

    /// Enumerates EventKit lists plus a synthetic default. Never prompts; a
    /// denied/unauthorized read degrades to the synthetic default only.
    @MainActor
    private func allEntities() async -> [ReminderListEntity] {
        let defaultEntity = ReminderListEntity(id: ReminderListEntity.defaultID, name: "Default (Inbox)")
        guard case .fullAccess = currentTargeting().accessStatus() else { return [defaultEntity] }
        guard let snapshot = try? await currentTargeting().reminderLists() else { return [defaultEntity] }
        return [defaultEntity] + snapshot.selectableOptions.map {
            ReminderListEntity(id: $0.id, name: $0.title)
        }
    }
}
