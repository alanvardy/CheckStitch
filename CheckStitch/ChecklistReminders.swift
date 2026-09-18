import CheckStitchCore
import Foundation
import os

enum ChecklistReminders {
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistReminders")

    /// Production entry point: requests access, resolves the checklist's
    /// destination (or the system default) BEFORE creating anything, then
    /// creates one reminder per non-blank item. Returns an outcome the caller
    /// can surface — permission denial and missing lists are no longer silent.
    static func create(from checklist: Checklist, prefixNumbers: Bool = false) async -> ReminderRunOutcome {
        await create(from: checklist, targeting: EventKitReminderDestination.shared, prefixNumbers: prefixNumbers)
    }

    static func create(from checklist: Checklist,
                       targeting: ReminderDestinationTargeting,
                       prefixNumbers: Bool = false) async -> ReminderRunOutcome {
        var created = 0
        do {
            guard try await targeting.requestAccess() else { return .permissionDenied }
            let snapshot = try await targeting.reminderLists()
            guard let destination = snapshot.resolve(checklist.destinationListIdentifier) else {
                // All-or-nothing: validate existence before the first create.
                return .destinationMissing
            }
            var position = 0
            for item in checklist.items where !item.isBlank {
                // Numbering is assigned after blank items are dropped, so an emptied
                // row never leaves a gap: item one is always 1.
                position += 1
                // Both paths compute the date from the same pure Core function;
                // `Date()` is the device-local today, matching the SingleThread
                // precedent. Items without a relative date keep no date.
                let dueDateComponents = item.dueDateComponents(today: Date())
                try await targeting.create(
                    title: ChecklistTitleNumbering.title(
                        item.title, position: position, numbered: prefixNumbers),
                    notes: item.hasDescription ? item.description : nil,
                    priority: item.priority,
                    in: destination,
                    dueDateComponents: dueDateComponents)
                created += 1
            }
            return .created(count: created)
        } catch {
            logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
            let total = checklist.items.filter { !$0.isBlank }.count
            if created > 0 {
                // Mid-loop throw: earlier items are already committed. Report the
                // exact split instead of a generic failure.
                return .partiallyCreated(created: created, total: total, reason: error.localizedDescription)
            }
            return .failed(error.localizedDescription)
        }
    }
}
