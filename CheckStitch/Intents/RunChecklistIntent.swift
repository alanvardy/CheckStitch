import AppIntents
import CheckStitchCore

/// Thrown when the entity id no longer resolves (checklist deleted between the
/// user's pick and `perform()`).
enum RunChecklistIntentError: LocalizedError {
    case checklistNotFound
    var errorDescription: String? {
        String(localized: "That checklist no longer exists.", table: "Localizable", bundle: .main)
    }
}

struct RunChecklistIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Checklist"
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Checklist")
    var checklist: ChecklistEntity

    // test seam; nil → fresh production collaborators
    private let injectedStore: ChecklistStore?
    private let injectedTargeting: (any ReminderDestinationTargeting)?

    init() { self.injectedStore = nil; self.injectedTargeting = nil }

    @MainActor
    init(store: ChecklistStore, targeting: ReminderDestinationTargeting) {
        self.injectedStore = store
        self.injectedTargeting = targeting
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$checklist)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = injectedStore ?? ChecklistStore(defaults: AppGroup.defaults)
        let targeting = injectedTargeting ?? EventKitReminderDestination.shared

        guard let uuid = UUID(uuidString: checklist.id),
              let stored = store.checklist(id: uuid)
        else { throw RunChecklistIntentError.checklistNotFound }

        // Status-only pre-check: a cold process may be unauthorized but must
        // never prompt from inside an intent. Residual TOCTOU: access revoked
        // between here and `create` lets its `requestAccess()` re-prompt —
        // accepted, same shape as the SingleThread reference.
        switch targeting.accessStatus() {
        case .fullAccess:
            break
        case .notDetermined:
            return .result(dialog: IntentDialog(RunChecklistDialogue.notDetermined))
        case .denied:
            return .result(dialog: IntentDialog(RunChecklistDialogue.denied))
        }

        let outcome = await ChecklistReminders.create(from: stored, targeting: targeting)
        return .result(dialog: IntentDialog(
            RunChecklistDialogue.message(for: outcome, checklistName: stored.name)))
    }
}

/// Outcome→speech mapping. Lives here (not in the intent body) so exact text is
/// unit-testable without a speech stack. Keys are in the app catalog.
enum RunChecklistDialogue {
    static let notDetermined = LocalizedStringResource(
        "Open CheckStitch and allow Reminders access, then ask again.",
        table: "Localizable", bundle: .main)
    static let denied = LocalizedStringResource(
        "CheckStitch doesn't have permission to access Reminders. Turn it on in Settings, then ask again.",
        table: "Localizable", bundle: .main)

    @MainActor
    static func message(for outcome: ReminderRunOutcome, checklistName: String) -> LocalizedStringResource {
        switch outcome {
        case .created(let count):
            guard count != 1 else {
                return LocalizedStringResource(
                    "Created 1 reminder for \(checklistName).", table: "Localizable", bundle: .main)
            }
            return LocalizedStringResource(
                "Created \(count) reminders for \(checklistName).", table: "Localizable", bundle: .main)
        case .destinationMissing:
            return LocalizedStringResource(
                "That list no longer exists, so no reminders were created for \(checklistName).",
                table: "Localizable", bundle: .main)
        case .permissionDenied:
            return denied
        case .partiallyCreated(let created, let total, let reason):
            return LocalizedStringResource(
                "Created \(created) of \(total) reminders for \(checklistName); the rest were not created. \(reason)",
                table: "Localizable", bundle: .main)
        case .failed(let reason):
            return LocalizedStringResource(
                "Couldn't create reminders for \(checklistName): \(reason)", table: "Localizable", bundle: .main)
        }
    }
}
