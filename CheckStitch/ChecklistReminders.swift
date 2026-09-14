import CheckStitchCore
import EventKit
import os

enum ChecklistReminders {
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistReminders")

    /// Production entry point: requests access, resolves the checklist's
    /// destination (or the system default) BEFORE creating anything, then
    /// creates one reminder per non-blank item. Returns an outcome the caller
    /// can surface — permission denial and missing lists are no longer silent.
    static func create(from checklist: Checklist) async -> ReminderRunOutcome {
        await create(from: checklist, targeting: EventKitReminderDestination.shared)
    }

    static func create(from checklist: Checklist, targeting: ReminderDestinationTargeting) async -> ReminderRunOutcome {
        do {
            guard try await targeting.requestAccess() else { return .permissionDenied }
            let snapshot = try await targeting.reminderLists()
            guard let destination = snapshot.resolve(checklist.destinationListIdentifier) else {
                // All-or-nothing: validate existence before the first create.
                return .destinationMissing
            }
            var created = 0
            for item in checklist.items where !item.isBlank {
                try await targeting.create(title: item.title, in: destination)
                created += 1
            }
            return .created(count: created)
        } catch {
            logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }
}