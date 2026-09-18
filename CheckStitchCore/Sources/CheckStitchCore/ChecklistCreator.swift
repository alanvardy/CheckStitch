import Foundation

/// Outcome of a checklist creation attempt. `permissionDenied` replaces the old
/// silent `return`, so denial is observable rather than a no-op.
public enum ChecklistCreationOutcome: Equatable, Sendable {
    case created(count: Int)
    case permissionDenied
    case failed(String)
}

/// Policy for optional 1-based numbering of created reminder titles.
///
/// Defined here, in the one policy seam that drops blank titles, so the format
/// exists in exactly one place; both `ChecklistCreator` and the app-side
/// `ChecklistReminders` apply it. Numbering is unbounded past 9.
public enum ChecklistTitleNumbering {
    /// `"<position>: <title>"` when `numbered`, otherwise `title` unchanged.
    public static func title(_ title: String, position: Int, numbered: Bool) -> String {
        numbered ? "\(position): \(title)" : title
    }
}

/// Owns the reminder-creation policy: ask permission, drop blank titles, create
/// one reminder per remaining item. Items with a relative date set a
/// date-only `dueDateComponents` on the reminder; the offset-to-date
/// arithmetic lives in `ChecklistItem.dueDateComponents`.
///
/// Declared `Sendable` explicitly — a `public` struct gets no inferred
/// conformance, and callers would otherwise fail to send it across isolation
/// boundaries.
public struct ChecklistCreator: Sendable {
    public init(reminders: ReminderCreating,
                now: @escaping @Sendable () -> Date = Date.init,
                calendar: Calendar = .current,
                prefixNumbers: Bool = false) {
        self.reminders = reminders
        self.now = now
        self.calendar = calendar
        self.prefixNumbers = prefixNumbers
    }

    public func create(from items: [ChecklistItem]) async -> ChecklistCreationOutcome {
        do {
            guard try await reminders.requestAccess() else { return .permissionDenied }
            var created = 0
            var position = 0
            let today = now()
            for item in items where !item.isBlank {
                // Position is assigned after blank items are dropped, so an emptied
                // row never leaves a gap: item one is always 1.
                position += 1
                try await reminders.create(
                    title: ChecklistTitleNumbering.title(
                        item.title, position: position, numbered: prefixNumbers),
                    dueDateComponents: item.dueDateComponents(today: today, calendar: calendar))
                created += 1
            }
            return .created(count: created)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private let reminders: ReminderCreating
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let prefixNumbers: Bool
}
