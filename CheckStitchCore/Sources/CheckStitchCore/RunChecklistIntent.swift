import AppIntents

/// Thrown when the entity id no longer resolves (checklist deleted between the
/// user's pick and `perform()`).
enum RunChecklistIntentError: LocalizedError {
    case checklistNotFound
    case invalidMultiple
    var errorDescription: String? {
        switch self {
        case .checklistNotFound:
            LocalizedStringResource(
                "That checklist no longer exists.", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
        case .invalidMultiple:
            LocalizedStringResource(
                "Multiple must be between 1 and 99.", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
        }
    }
}

public struct RunChecklistIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Checklist"
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Checklist")
    public var checklist: ChecklistEntity

    @Parameter(title: "Multiple")
    public var multiple: Int?

    // test seam; nil → fresh production collaborators
    private let injectedStore: ChecklistStore?
    private let injectedTargeting: (any ReminderDestinationTargeting)?
    private let injectedGate: RunGate?
    private let injectedRunState: WidgetRunStateStore?

    public init() {
        self.injectedStore = nil
        self.injectedTargeting = nil
        self.injectedGate = nil
        self.injectedRunState = nil
    }

    @MainActor
    public init(store: ChecklistStore, targeting: ReminderDestinationTargeting, gate: RunGate,
                runState: WidgetRunStateStore? = nil) {
        self.injectedStore = store
        self.injectedTargeting = targeting
        self.injectedGate = gate
        self.injectedRunState = runState
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$checklist)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = injectedStore ?? ChecklistStore(defaults: AppGroup.defaults)
        let targeting = injectedTargeting ?? EventKitReminderDestination.shared

        guard let uuid = UUID(uuidString: checklist.id),
              let stored = store.checklist(id: uuid)
        else { throw RunChecklistIntentError.checklistNotFound }

        // Validate before the status pre-check and before any side effect, so a bad
        // override can never reserve a run slot or create a reminder.
        if let multiple, !Checklist.multipleRange.contains(multiple) {
            throw RunChecklistIntentError.invalidMultiple
        }

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

        let gate = await resolveGate()
        // The widget button's feedback lives here: a run recorded as `.running`
        // (plus the reload the store fires) lets a timeline reload render the
        // spinner, and the finished record drives the checkmark. The app path
        // holds the same state in `ChecklistRunViewModel` instead.
        let runState = injectedRunState ?? WidgetRunStateStore()
        runState.beginRun(id: uuid, at: Date())
        // Hold the spinner for at least `minimumSpinner` so a fast EventKit save
        // cannot flash past the user; tests inject zero.
        async let minimumSpinner: Void = Task.sleep(for: .seconds(runState.minimumSpinner))
        let outcome = await ChecklistReminders.create(
            from: stored,
            targeting: targeting,
            gate: gate,
            multipleOverride: multiple)
        try? await minimumSpinner
        runState.finishRun(id: uuid, didCreate: outcome.didCreateAllItems, at: Date())
        return .result(dialog: IntentDialog(
            RunChecklistDialogue.message(for: outcome, checklistName: stored.name)))
    }

    /// The injected gate when present (tests), else the shared production gate.
    @MainActor
    private func resolveGate() async -> RunGate {
        if let injectedGate { return injectedGate }
        return await ChecklistReminders.productionGate()
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
        case .purchaseRequired:
            return LocalizedStringResource(
                "You've reached the CheckStitch free limit. Open CheckStitch to buy a license.",
                table: "Localizable", bundle: .main)
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