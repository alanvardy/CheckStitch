# Structure Outline

## Approach

Two App Intents in the app target (`CheckStitch/Intents/`) built on the existing
production seam (`ChecklistReminders` + `ReminderDestinationTargeting`), reading a
fresh `ChecklistStore` per `perform()`. The one risky integration is App Intents
itself (declaration → metadata extraction → headless dispatch → `AppEntity`
parameter), so slice 1 proves it end to end rather than letting it hide until the
end; the Core enum/seam changes ride alongside the slices that consume them.

---

## Phase 1: Walking skeleton — "Run Groceries" creates the reminders, and says exactly what happened

From Siri/Shortcuts the user picks a checklist by name (`AppEntity` parameter over
`store.checklists`) and its non-blank items become Reminders in the checklist's own
destination list, with title, notes and due date mapped. The spoken answer reports
the count, or names *why* nothing was created (destination list gone, access not
granted, access never asked for). This is the whole framework unknown plus the real
EventKit path, wired and tested in one commit.

**Spike checkpoint before real bodies**: one throwaway stub intent + provider,
compiled by `make build` and `make build-mac`, to confirm the AppIntents build phase
emits metadata. If it does not, drop `CheckStitchShortcuts.swift` (decision 9) and
continue via Shortcuts.app — do not block the slice.

**Files** (app target + Core seam + catalog):
- `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift` — access-status read added to the seam
- `CheckStitch/EventKitReminderDestination.swift` — real implementation
- `CheckStitch/Intents/ChecklistEntity.swift` — `AppEntity` + `EntityStringQuery`
- `CheckStitch/Intents/RunChecklistIntent.swift` — the intent
- `CheckStitch/Intents/CheckStitchShortcuts.swift` — one phrase
- `CheckStitch/Localizable.xcstrings` — dialogue keys, all six languages
- `CheckStitchTests/TestFixtures.swift` — `SpyReminderDestination` gains the new requirement (default keeps the 13 existing tests green)

**Key changes**:
- `enum ReminderAccessStatus { case fullAccess, notDetermined, denied }` — new (Core), with its own user-facing `message`
- `func accessStatus() -> ReminderAccessStatus` — new requirement on `ReminderDestinationTargeting`; implemented with `EKEventStore.authorizationStatus(for: .reminder)` (never `requestAccess()` — that can prompt)
- `struct ChecklistEntity: AppEntity { let id: String /* Checklist.id.uuidString */, name: String; var displayRepresentation }` — new; id is rename- and sync-stable
- `struct ChecklistEntityQuery: EntityStringQuery` — `entities(for:)`, `entities(matching:)`, `suggestedEntities()` over `store.checklists` display order
- `@MainActor func RunChecklistDialogue.message(for outcome: ReminderRunOutcome, checklistName: String) -> LocalizedStringResource` — new (Core, beside the other outcome text); the outcome→speech mapping, unit-testable without a speech stack
- `struct RunChecklistIntent: AppIntent` — `static let title: LocalizedStringResource`, `static let openAppWhenRun = false`, `@Parameter var checklist: ChecklistEntity`, `@MainActor init()`, `@MainActor init(store:targeting:)` (test seam), `@MainActor func perform() async throws -> some IntentResult & ProvidesDialog`
- `struct CheckStitchShortcuts: AppShortcutsProvider` — one `AppShortcut` for the run intent

**Contract**: `ChecklistEntity` + `ChecklistEntityQuery` (id = `uuidString`, display name = `name`, display order preserved); `ReminderAccessStatus`; `RunChecklistDialogue.message(for:checklistName:)`; `RunChecklistIntent.init(store:targeting:)` for test injection. Later slices consume these and nothing else of this slice's internals.

**Tests**: `RunChecklistIntentTests` — creates all non-blank items, exact dialogue text for `.created`; stale entity id throws the "checklist no longer exists" error with its message; `notDetermined` and `denied` each produce their distinct instruction dialogue and zero creates (happy + 3 sad paths). `ChecklistEntityQueryTests` — all entities, string match, by-id, rename-stable id, empty store. `LocalizationTests` — new keys present in all six languages and differing from English.
**Verify**: `make test-unit` green for this slice; `make build-mac` shows the intent metadata; manual: `make build-mac-signed`, both actions visible in Shortcuts.app, spoken run creates the reminders in the resolved list.

---

## Phase 2: Partial creation is reported exactly, not as a generic failure

When the destination list disappears *mid-run*, the earlier items are already in
Reminders. Today the count is discarded and Siri/the app say only "failed". After
this slice Siri says "Created 3 of 7 reminders for Groceries; the rest were not
created." and the in-app alert carries the same text.

*Small horizontal step, kept inside a slice*: `ReminderRunOutcome` gains a case and
every `switch` over it is updated in the same commit, so the tree stays exhaustive
and green.

**Files**:
- `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift` — new case + `errorMessage`
- `CheckStitch/ChecklistReminders.swift` — count-aware `catch`
- `CheckStitch/ContentView.swift` — switch gains the case
- `CheckStitch/Intents/RunChecklistIntent.swift` — dialogue for the new case
- `CheckStitch/Localizable.xcstrings` — the partial-creation key, six languages

**Key changes**:
- `case partiallyCreated(created: Int, total: Int, reason: String)` added to `ReminderRunOutcome`
- `ChecklistReminders.create(from:)` returns it instead of `.failed` when the `catch` fires with `created > 0`; `total` = non-blank item count
- `RunChecklistDialogue.message` handles the case (created/total/name/reason)

**Contract**: `.failed` is never returned once at least one item was created; `partiallyCreated` counts are (created, total-non-blank). Both consumers (dialog + alert) read the same `errorMessage`/dialogue text.

**Tests**: `ChecklistRemindersTests` — mid-loop throw at the 3rd of 7 → `.partiallyCreated(created: 3, total: 7, …)` and its exact `errorMessage`; throw before any create still yields `.failed`; existing `.destinationMissing` zero-creation case unchanged. `RunChecklistIntentTests` — exact partial dialogue.
**Verify**: `make test-unit`; the `ContentView` switch compiles under `make build`.

---

## Phase 3: "List My Checklists" — the side-effect-free spoken query

"List my checklists in CheckStitch" answers "You have 3 checklists: Groceries,
Packing, Chores." or "You don't have any checklists yet.". No app launch, no writes.

**Files**:
- `CheckStitch/Intents/ListChecklistsIntent.swift` — new intent
- `CheckStitch/Intents/ChecklistEntity.swift` — reuse `ChecklistEntityQuery.suggestedEntities()`
- `CheckStitch/Intents/CheckStitchShortcuts.swift` — second phrase
- `CheckStitch/Localizable.xcstrings` — list + empty-state keys, six languages

**Key changes**:
- `struct ListChecklistsIntent: AppIntent` — no parameters, `openAppWhenRun = false`, `@MainActor init(store:query:)` test seam, `perform() async throws -> some IntentResult & ProvidesDialog`
- `ListChecklistsDialogue.message(for: [String]) -> LocalizedStringResource` — names joined in display order; distinct empty-state string

**Contract**: reads only via Phase 1's `ChecklistEntityQuery`; performs no store mutation and touches no EventKit type. Anything added to the query later is automatically reflected here.

**Tests**: `ListChecklistsIntentTests` — three checklists render in display order with the exact dialogue; empty store renders the empty-state line; assert the store is unmodified after `perform()`.
**Verify**: `make test-unit`; manual: both phrases resolve in Shortcuts.app and via Siri.

---

## Phase 4: Hardening — the states the happy path never saw

The intents stay correct when dispatched into a cold process, when access is granted
between two asks, when the store is stale/pre-sync, and with long or numerous
checklist names; every new dialogue is present in all six languages and the full
gate covers the simulator, macOS and watch legs.

**Files**:
- `CheckStitch/Intents/*.swift` — guards for the states below
- `CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift` — every dialogue key added to `requiredKeys` so it cannot be dropped
- `CheckStitch/Intents/CheckStitchShortcuts.swift` — only if the metadata fallback was needed

**Key changes**:
- Cold-dispatch path: `perform()` never depends on scene/`@State` (fresh store per run); no `openAppWhenRun`
- `notDetermined` after a prior `denied`, and denial re-ask, produce stable distinct text
- Long-name / many-checklist dialogue remains well-formed (no truncation assumptions)

**Contract**: no behaviour change to Phases 1–3 contracts; the intents remain constructible with `init()` and `init(store:targeting:)`.

**Tests**: extended `RunChecklistIntentTests` / `ListChecklistsIntentTests` for the above; `LocalizationTests` full suite; `bash scripts/tests/run.sh`.
**Verify**: `bash scripts/test.sh` prints `gate: ok` (incl. `make build-mac`, `make watch-build` — the watch target must not compile the intents); manual device pass on the signed macOS build.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` green **and** `make build-mac` emits intent metadata. If metadata extraction fails, apply the provider fallback before continuing.
- After Phase 2: `make test-unit` green; no `switch` over `ReminderRunOutcome` is non-exhaustive (`make build`).
- After Phase 3: `make test-unit` green; both phrases discoverable in Shortcuts.app.
- After Phase 4: `bash scripts/test.sh` prints `gate: ok`; manual signed-build pass on the real device. Never advance past a failing checkpoint.
