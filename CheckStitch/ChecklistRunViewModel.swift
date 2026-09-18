import CheckStitchCore
import Foundation
import Observation

/// Drives one checklist's "create reminders" run. Independent of the list VM;
/// consumes the existing `ChecklistReminders` seam so tests inject
/// `SpyReminderDestination` and never touch EventKit.
@MainActor
@Observable
final class ChecklistRunViewModel {
    /// `spinnerDuration` is the minimum time the spinner stays visible once the
    /// run finishes; suites inject `.zero` to keep tests instant.
    init(
        store: ChecklistStore,
        targeting: ReminderDestinationTargeting = EventKitReminderDestination.shared,
        spinnerDuration: Duration = .seconds(1)
    ) {
        self.store = store
        self.targeting = targeting
        self.spinnerDuration = spinnerDuration
    }

    /// Checklists with a run in flight. Never persisted.
    private(set) var creating: Set<UUID> = []
    /// Checklists showing the transient success check. Never persisted.
    private(set) var created: Set<UUID> = []
    /// Message for the run-failure alert; `nil` hides it.
    private(set) var runErrorMessage: String?

    /// Guards against duplicate taps synchronously (before the first `await`),
    /// then runs one checklist.
    func createReminders(for id: UUID) async {
        guard !creating.contains(id), let checklist = store.checklist(id: id) else { return }
        creating.insert(id)
        // Hold the spinner for at least `spinnerDuration` so saving quickly
        // doesn't flash the progress feedback past the user.
        async let minimumSpinner: Void = Task.sleep(for: spinnerDuration)
        let outcome = await ChecklistReminders.create(from: checklist, targeting: targeting)
        try? await minimumSpinner
        creating.remove(id)
        switch outcome {
        case .created:
            created.insert(id)
            try? await Task.sleep(for: .seconds(1))
            created.remove(id)
        case .destinationMissing, .permissionDenied, .partiallyCreated, .failed:
            // Never flash success: nothing (or only part) was created.
            runErrorMessage = outcome.errorMessage
        }
    }

    /// Clears the failure alert.
    func clearRunError() {
        runErrorMessage = nil
    }

    private let store: ChecklistStore
    private let targeting: ReminderDestinationTargeting
    private let spinnerDuration: Duration
}