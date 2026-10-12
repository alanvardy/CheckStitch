import AppIntents

/// Test seam for resolving a Prompt-mode scaling number. The production
/// implementation asks through the intent's own optional `@Parameter`; suites
/// inject a fake so no system request machinery is needed.
@MainActor
protocol ScalingPrompting: Sendable {
    func requestMultiple(prompt: LocalizedStringResource) async throws -> Int
}

/// Production prompter: asks the system for the `multiple` parameter's value.
@MainActor
struct AppIntentScalingPrompter: ScalingPrompting {
    let parameter: IntentParameter<Int?>

    func requestMultiple(prompt: LocalizedStringResource) async throws -> Int {
        // `requestValue` returns the unwrapped `Int` because `Value.ValueType` is
        // the non-optional `Wrapped.ValueType` for an `Int?` parameter, and it
        // presents the dialog it is handed; a cancelled or headless request
        // surfaces as an error (e.g. `CancellationError`) instead of a value.
        return try await parameter.requestValue(IntentDialog(prompt))
    }
}

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

    @Parameter(title: "List")
    public var destination: ReminderListEntity?

    // test seam; nil → fresh production collaborators
    private let injectedStore: ChecklistStore?
    private let injectedTargeting: (any ReminderDestinationTargeting)?
    private let injectedGate: RunGate?
    private let injectedRunState: WidgetRunStateStore?
    /// test seam; nil → ask the system parameter prompt via `$destination`.
    /// Injected so tests can drive the prompt/no-value path without a host.
    var destinationRequester: (@MainActor () async -> ReminderListEntity?)?
    private let injectedPrompter: (any ScalingPrompting)?

    public init() {
        self.injectedStore = nil
        self.injectedTargeting = nil
        self.injectedGate = nil
        self.injectedRunState = nil
        self.destinationRequester = nil
        self.injectedPrompter = nil
    }

    @MainActor
    init(store: ChecklistStore, targeting: ReminderDestinationTargeting, gate: RunGate,
         prompter: (any ScalingPrompting)? = nil, runState: WidgetRunStateStore? = nil) {
        self.injectedStore = store
        self.injectedTargeting = targeting
        self.injectedGate = gate
        self.injectedRunState = runState
        self.destinationRequester = nil
        self.injectedPrompter = prompter
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$checklist)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = injectedStore ?? ChecklistStore(defaults: AppGroup.defaults)
        let targeting = injectedTargeting ?? EventKitReminderDestination.shared

        guard let uuid = UUID(uuidString: checklist.id),
              let stored = store.checklist(id: uuid),
              !stored.isArchived
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

        // A `.prompt` checklist resolves at run time through the system parameter
        // prompt; a headless call with no presenter reports instead of defaulting.
        var resolvedDestination: ChecklistDestination? = nil
        if stored.destination == .prompt {
            if let entity = await requestedDestination() {
                resolvedDestination = entity.id == ReminderListEntity.defaultID
                    ? .systemDefault
                    : .list(entity.id)
            } else {
                // No presenter (headless automation); report rather than silently default.
                return .result(dialog: IntentDialog(RunChecklistDialogue.destinationRequired))
            }
        } else {
            resolvedDestination = stored.destination
        }

        // Prompt mode with no explicit argument asks the system for a number. An
        // explicit `multiple` always wins, preserving existing automations. A
        // failure (headless automation, widget button, cancelled request) falls
        // back to the existing dialog path and creates nothing.
        var resolvedMultiple = multiple
        if resolvedMultiple == nil, stored.scaling.isPrompt {
            let prompter: any ScalingPrompting =
                injectedPrompter ?? AppIntentScalingPrompter(parameter: $multiple)
            do {
                let requested = try await prompter.requestMultiple(prompt: RunChecklistDialogue.scalingPrompt)
                guard Checklist.multipleRange.contains(requested) else {
                    throw RunChecklistIntentError.invalidMultiple
                }
                resolvedMultiple = requested
            } catch let error as RunChecklistIntentError {
                throw error
            } catch {
                return .result(dialog: IntentDialog(RunChecklistDialogue.scalingPromptUnavailable))
            }
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
            multipleOverride: resolvedMultiple,
            destination: resolvedDestination)
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

    /// The destination the user picked. Prefers the already-present `destination`
    /// parameter; otherwise asks the system (root parameter prompt) for it. A
    /// cancelled/silent ask yields `nil` — the caller reports `.destinationRequired`.
    @MainActor
    private func requestedDestination() async -> ReminderListEntity? {
        if let destination { return destination }
        if let destinationRequester { return await destinationRequester() }
        return try? await $destination.requestValue()
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
    static let destinationRequired = LocalizedStringResource(
        "Open CheckStitch to choose a list, then run this checklist again.",
        table: "Localizable", bundle: .main)
    static let scalingPrompt = LocalizedStringResource(
        "How many times should this scale?", table: "Localizable", bundle: .main)
    static let scalingPromptUnavailable = LocalizedStringResource(
        "CheckStitch couldn't ask for a scaling number. Run the checklist in the app, or pass a Multiple value.",
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
        // The funnel can still return this if the override never arrived (e.g. a
        // headless call between the Siri/Shortcuts picker and Run resolves nothing).
        case .destinationRequired:
            return destinationRequired
        }
    }
}
