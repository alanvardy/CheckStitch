# Q5 — App Intents parameter & validation patterns (as-is)

## RunChecklistIntent (CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift)
- struct RunChecklistIntent: AppIntent (line 15): static title (line 16, "Run Checklist"), openAppWhenRun: Bool = false (line 17).
- One @Parameter field (lines 20-21): @Parameter(title: "Checklist") public var checklist: ChecklistEntity — required, singular, non-optional entity ref.
- parameterSummary (lines 38-40): Summary that composes the chosen checklist into the speech summary.
- Test-seam ctor injects injectedStore, injectedTargeting, injectedGate, injectedRunState (lines 23-26, 28-35); prod @MainActor ctor has runState: WidgetRunStateStore? = nil default.

## Validation shape (enum : LocalizedError)
- enum RunChecklistIntentError: LocalizedError { case checklistNotFound } with var errorDescription: String? returning LocalizedStringResource(...).resolvedInAppLanguage() (lines 5-13). Single error case; no .invalid... enum variants, no prefix-style error cases — validation surfaces as a thrown LocalizedError.
- Test asserts it (CheckStitchTests/RunChecklistIntentTests.swift:65-68): catches RunChecklistIntentError and expects errorDescription == "That checklist no longer exists.".

## Validation-before-side-effects ordering in perform() (lines 48-94)
1. resolve collaborators (store, targeting) (lines 49-50).
2. guard uuid = UUID(uuidString: checklist.id), stored = store.checklist(id: uuid) else { throw ...checklistNotFound } (lines 52-55) — the only throwing validation, and it runs before any side effect.
3. Status-only pre-check switch on targeting.accessStatus() (lines 57-66): .fullAccess proceeds; .notDetermined and .denied return dialogs (no throw, no run).
4. THEN side effects: resolveGate() (line 68), runState.beginRun (line 78), ChecklistReminders.create (line 80), finishRun (line 85), final IntentDialog return (lines 86-88). Comment (lines 53-55) documents residual TOCTOU: access checks are pre-side-effect; a revoked grant between pre-check and create lets requestAccess() re-prompt.
- Outcome dialogue mapping lives in separate enum RunChecklistDialogue (lines 91-129) — intent body stays text-free.

## Sibling intents (AppIntent / WidgetConfigurationIntent)
- ListChecklistsIntent (ListChecklistsIntent.swift): no @Parameter fields — only private query: ChecklistEntityQuery injected ctor (lines 8-11), openAppWhenRun=false, no parameterSummary. perform() (lines 14-18) calls suggestedEntities() and maps .name; no throws/validation.
- ChecklistConfigurationIntent (ChecklistConfigurationIntent.swift): struct : WidgetConfigurationIntent, static title/description (lines 4-6), ONE optional param (lines 8-9): @Parameter(title: "Checklist") public var checklist: ChecklistEntity? — nullable (?) marks it optional for widget config. Empty init().
- MultiChecklistConfigurationIntent (MultiChecklistConfigurationIntent.swift): same WidgetConfigurationIntent shape, optional collection (lines 8-9): @Parameter(title: "Checklists") public var checklists: [ChecklistEntity]? — custom array-of-entity parameter, nullable. Empty init(), no perform().

## Entity types (ChecklistEntity.swift)
- struct ChecklistEntity: AppEntity (lines 6-15): id: String (Checklist.id.uuidString, rename-proof), name: String, displayRepresentation = DisplayRepresentation(title).
- ChecklistEntityQuery: EntityStringQuery (lines 17-38): ctor with nil store or injected store; fresh store per call (currentStore(), lines 29-31); three methods entities(for identifiers:), entities(matching:), suggestedEntities() — the last is what List/Run intents default to.

## Patterns summary
- Optional vs required = T? nullable vs bare T; multi uses [T]?.
- No shared .invalid... error enum; each throwing intent declares its own enum ...: LocalizedError with errorDescription returning a resolved LocalizedStringResource (Localizable table, bundle .main).
- All validation precedes any side effect in perform(); dialogues are factored into separate enums.
