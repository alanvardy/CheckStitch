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
        counter: RunCounter = RunCounter(defaults: AppGroup.defaults),
        purchases: PurchaseService = PurchaseEnvironment.service,
        spinnerDuration: Duration = .seconds(1)
    ) {
        self.store = store
        self.targeting = targeting
        self.counter = counter
        self.purchases = purchases
        self.spinnerDuration = spinnerDuration
    }

    /// Checklists with a run in flight. Never persisted.
    private(set) var creating: Set<UUID> = []
    /// Checklists showing the transient success check. Never persisted.
    private(set) var created: Set<UUID> = []
    /// Message for the run-failure alert; `nil` hides it.
    private(set) var runErrorMessage: String?
    /// Present when a run was refused at the free limit.
    private(set) var isShowingPaywall = false
    /// The checklist whose `.prompt` run is waiting for a one-shot destination
    /// choice. Never persisted. `nil` hides the chooser sheet.
    private(set) var destinationPrompt: Checklist?
    /// The lists a `.prompt` run offers as explicit choices (`selectableOptions`,
    /// so the system default is absent — the sheet's default row stands for it).
    private(set) var destinationOptions: [ReminderListOption] = []

    /// The checklist whose run is waiting for a Prompt-mode number; `nil` hides
    /// the sheet. Never persisted.
    private(set) var promptingRunID: UUID?

    /// The checklist waiting for a Prompt-mode number, or `nil`. Drives the sheet.
    var promptingChecklist: Checklist? {
        guard let promptingRunID else { return nil }
        return store.checklist(id: promptingRunID)
    }

    /// Starts a run: `.fixed` runs immediately, `.prompt` parks the run behind
    /// the scaling sheet. Never writes the mode or number back. Returns the
    /// spawned run task for a `.fixed` run so suites can await it; `nil` when
    /// nothing runs (guard miss or parked prompt).
    @discardableResult
    func startRun(for id: UUID) -> Task<Void, Never>? {
        guard !creating.contains(id),
              let checklist = store.checklist(id: id),
              checklist.hasRunnableItems
        else { return nil }
        if checklist.scaling.isPrompt {
            promptingRunID = id
            return nil
        } else {
            return Task { await createReminders(for: id) }
        }
    }

    /// Dismisses the scaling sheet without running.
    func cancelPrompt() {
        promptingRunID = nil
    }

    /// Runs the parked checklist with the entered factor as a per-run override.
    /// Returns the spawned run task so suites can await it deterministically.
    @discardableResult
    func confirmPrompt(multiple: Int) -> Task<Void, Never>? {
        guard let id = promptingRunID else { return nil }
        promptingRunID = nil
        return Task { await createReminders(for: id, multipleOverride: multiple) }
    }

    /// Guards against duplicate taps synchronously (before the first `await`),
    /// then runs one checklist. `multipleOverride` is per-run only and never
    /// persisted.
    func createReminders(for id: UUID, multipleOverride: Int? = nil) async {
        guard !creating.contains(id),
              let checklist = store.checklist(id: id),
              checklist.hasRunnableItems
        else { return }
        await perform(checklist: checklist, multipleOverride: multipleOverride, destination: nil)
    }

    /// Runs again with the sheet's one-shot choice; never written back to the store.
    func run(_ checklist: Checklist, in destination: ChecklistDestination) async {
        destinationPrompt = nil
        await perform(checklist: checklist, destination: destination)
    }

    /// Widget deep-link entry point (`checkstitch://run?checklist=<id>`, wired in
    /// a later phase): presents the prompt chooser for a runnable, non-archived
    /// `.prompt` checklist. A no-op for any other checklist.
    func presentDestinationPrompt(forChecklistID id: UUID) async {
        guard let checklist = store.checklist(id: id),
              !checklist.isArchived, checklist.destination == .prompt,
              checklist.hasRunnableItems
        else { return }
        await presentPrompt(for: checklist)
    }

    func dismissDestinationPrompt() {
        destinationPrompt = nil
    }

    /// Parses a widget deep link (`checkstitch://run?checklist=<id>`) into its
    /// checklist id, or `nil` for any other URL — including a malformed
    /// `checkstitch://run` (no `checklist` query, non-UUID value, wrong scheme
    /// or host). Kept as a pure static so the deep-link routing is unit-testable.
    static func destinationPromptChecklistID(from url: URL) -> UUID? {
        guard url.scheme == "checkstitch", url.host == "run",
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "checklist" })?.value
        else { return nil }
        return UUID(uuidString: raw)
    }

    /// Runs one checklist through the seam. `destination` is the one-shot prompt
    /// override, or `nil` for the normal (non-prompt) path; a `.prompt` checklist
    /// with no override gets `.destinationRequired` and opens the chooser.
    private func perform(checklist: Checklist, multipleOverride: Int? = nil, destination: ChecklistDestination?) async {
        creating.insert(checklist.id)
        // Hold the spinner for at least `spinnerDuration` so saving quickly
        // doesn't flash the progress feedback past the user.
        async let minimumSpinner: Void = Task.sleep(for: spinnerDuration)
        // Resolve entitlement before reading it, so a cold launch cannot evaluate
        // the gate against a stale `.unknown` (the intent path does the same).
        await purchases.start()
        let gate = RunGate(counter: counter, isUnlocked: purchases.isUnlocked)
        let outcome = await ChecklistReminders.create(
            from: checklist, targeting: targeting, gate: gate,
            multipleOverride: multipleOverride, destination: destination)
        try? await minimumSpinner
        creating.remove(checklist.id)
        switch outcome {
        case .created:
            created.insert(checklist.id)
            try? await Task.sleep(for: .seconds(1))
            created.remove(checklist.id)
        case .purchaseRequired:
            isShowingPaywall = true
        case .destinationRequired:
            await presentPrompt(for: checklist)
        case .destinationMissing, .permissionDenied, .partiallyCreated, .failed:
            // Never flash success: nothing (or only part) was created.
            runErrorMessage = outcome.errorMessage
        }
    }

    /// Enumerates lists for the one-shot chooser. With no lists at all, routes to
    /// the missing-destination text instead of showing an empty sheet.
    private func presentPrompt(for checklist: Checklist) async {
        do {
            let snapshot = try await targeting.reminderLists()
            guard !snapshot.options.isEmpty || snapshot.defaultIdentifier != nil else {
                runErrorMessage = ReminderRunOutcome.destinationMissing.errorMessage
                return
            }
            destinationOptions = snapshot.selectableOptions
            destinationPrompt = checklist
        } catch {
            runErrorMessage = ReminderRunOutcome.permissionDenied.errorMessage
        }
    }

    /// Clears the failure alert.
    func clearRunError() {
        runErrorMessage = nil
    }

    func dismissPaywall() {
        isShowingPaywall = false
    }

    private let store: ChecklistStore
    private let targeting: ReminderDestinationTargeting
    private let counter: RunCounter
    private let purchases: PurchaseService
    private let spinnerDuration: Duration
}
