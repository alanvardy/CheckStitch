import Foundation

/// One selectable Reminders list. `id` is `EKCalendar.calendarIdentifier` — stable
/// across list renames and app restarts, unlike the title.
public struct ReminderListOption: Equatable, Identifiable, Sendable {
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public let id: String
    public let title: String
}

/// The Reminders lists visible at one instant, plus which one the system would
/// use by default (nil when there is no default list — treated as a failure,
/// never a silent skip).
public struct ReminderListsSnapshot: Equatable, Sendable {
    public init(options: [ReminderListOption], defaultIdentifier: String?) {
        self.options = options
        self.defaultIdentifier = defaultIdentifier
    }

    public let options: [ReminderListOption]
    public let defaultIdentifier: String?

    /// Resolves a stored destination to a selectable list. `nil` means "system
    /// default". Returns nil when the requested list (or the default) is gone,
    /// which the orchestrator turns into `.destinationMissing` before creating
    /// anything.
    public func resolve(_ identifier: String?) -> ReminderListOption? {
        if let identifier {
            return options.first { $0.id == identifier }
        }
        guard let defaultIdentifier else { return nil }
        return options.first { $0.id == defaultIdentifier }
    }

    /// The lists a picker should offer as explicit choices. The system default
    /// is left out: `options` already contains it (EventKit returns the default
    /// calendar alongside every other list), and the picker's own default row
    /// stands for it — keeping both would list the same list twice.
    public var selectableOptions: [ReminderListOption] {
        guard let defaultIdentifier else { return options }
        return options.filter { $0.id != defaultIdentifier }
    }

    /// The picker selection for a stored destination. A stored identifier that
    /// *is* the system default renders as the default row (`nil`), matching
    /// `selectableOptions`; every other value (including `nil`) passes through.
    public func pickerSelection(for stored: String?) -> String? {
        stored == defaultIdentifier ? nil : stored
    }
}

/// Outcome of a checklist run. `.destinationMissing` is distinct from `.failed`
/// so the UI can explain the missing-list case specifically.
public enum ReminderRunOutcome: Equatable, Sendable {
    case created(count: Int)
    case destinationMissing
    case permissionDenied
    case failed(String)

    /// User-facing text for every non-success outcome, `nil` on success. Kept
    /// here (not in the view) so the mapping is unit-testable.
    public var errorMessage: String? {
        switch self {
        case .created: return nil
        case .destinationMissing: return "That list no longer exists; no reminders were created."
        case .permissionDenied: return "CheckStitch doesn't have permission to access Reminders; no reminders were created."
        case .failed(let message): return message
        }
    }
}

/// Seam over the EventKit surface the run path needs: permission, list
/// enumeration, and creating a reminder in a chosen list. Injected so tests can
/// drive denial/missing-list/save-failure without touching EventKit.
///
/// `dueDateComponents` is the date-only reminder date (or `nil` for none); see
/// `ChecklistItem.dueDateComponents` — the run path never does offset arithmetic
/// itself. `priority`'s raw value is written straight through to
/// `EKReminder.priority` (none→0, low→9, medium→5, high→1), so no case mapping
/// exists at this boundary.
@MainActor
public protocol ReminderDestinationTargeting: Sendable {
    func requestAccess() async throws -> Bool
    /// Status-only read: never triggers the system prompt (unlike
    /// `requestAccess()`), so intents can fail cleanly instead of prompting.
    func accessStatus() -> ReminderAccessStatus
    func reminderLists() async throws -> ReminderListsSnapshot
    func create(title: String, notes: String?, priority: ChecklistItemPriority,
                in list: ReminderListOption, dueDateComponents: DateComponents?) async throws
}

/// Whether the app may create reminders right now, read without prompting.
public enum ReminderAccessStatus: Equatable, Sendable {
    case fullAccess
    case notDetermined
    case denied
}
