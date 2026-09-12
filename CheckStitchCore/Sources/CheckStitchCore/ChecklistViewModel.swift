import Foundation
import Observation
import os

/// Drives the checklist screen: owns the editable rows, the checklist name, and
/// the create/spinner/success flags.
@Observable
@MainActor
public final class ChecklistViewModel {
    /// `spinnerDuration` is the minimum time the spinner stays visible once
    /// creation finishes; suites inject `.zero` to keep tests instant.
    public init(environment: AppEnvironment, spinnerDuration: Duration = .seconds(1)) {
        creator = ChecklistCreator(reminders: environment.reminderCreator)
        self.spinnerDuration = spinnerDuration
    }

    public var checklistName = "checklist"
    public var items = [
        ChecklistItem(title: "one"),
        ChecklistItem(title: "two"),
        ChecklistItem(title: "three"),
    ]
    public private(set) var isCreatingChecklist = false
    public private(set) var isChecklistCreated = false

    /// Creates one reminder per non-blank item. Denial and failure leave the
    /// success flag false instead of silently returning.
    public func createChecklist() async {
        isCreatingChecklist = true
        // Hold the spinner for at least `spinnerDuration` so saving quickly
        // doesn't flash the progress feedback past the user.
        async let minimumSpinner: Void = Task.sleep(for: spinnerDuration)
        let outcome = await creator.create(from: items)
        try? await minimumSpinner
        isCreatingChecklist = false
        switch outcome {
        case .created:
            isChecklistCreated = true
        case .permissionDenied:
            break
        case .failed(let message):
            Self.logger.error(
                "Failed to create checklist reminders: \(message, privacy: .public)")
        }
    }

    /// Clears the success checkmark once the view's flash window elapses.
    public func dismissCreatedFeedback() {
        isChecklistCreated = false
    }

    private static let logger = Logger(
        subsystem: "app.alanvardy.CheckStitch", category: "Checklist")

    private let creator: ChecklistCreator
    private let spinnerDuration: Duration
}
