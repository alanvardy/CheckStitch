import Foundation

/// Outcome of a checklist creation attempt. `permissionDenied` replaces the old
/// silent `return`, so denial is observable rather than a no-op.
public enum ChecklistCreationOutcome: Equatable, Sendable {
    case created(count: Int)
    case permissionDenied
    case failed(String)
}

/// Owns the reminder-creation policy: ask permission, drop blank titles, create
/// one reminder per remaining item.
///
/// Declared `Sendable` explicitly — a `public` struct gets no inferred
/// conformance, and `ChecklistViewModel` would otherwise fail to send it.
public struct ChecklistCreator: Sendable {
    public init(reminders: ReminderCreating) {
        self.reminders = reminders
    }

    public func create(from items: [ChecklistItem]) async -> ChecklistCreationOutcome {
        do {
            guard try await reminders.requestAccess() else { return .permissionDenied }
            var created = 0
            for item in items where !item.isBlank {
                try await reminders.create(title: item.title)
                created += 1
            }
            return .created(count: created)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private let reminders: ReminderCreating
}