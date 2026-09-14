# Structure Outline

## Approach
Persist an optional `destinationListIdentifier: String?` on `Checklist` (nil = system
default), make it a first-class synced/merged field in the existing codec + store + merge,
then rework the production run path into an outcome-returning, pre-validating orchestrator
(`ChecklistReminders`) sitting on a small injectable EventKit destination seam, and finally
surface selection (detail screen `Picker`) and run failures (list-screen alert).

---

## Stage 1: Model + codec — persist the destination field
The field exists, decodes as `nil` for every existing v2 payload, and round-trips through
the single encoder unchanged. No `currentVersion` bump, no storage-key migration.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitchTests/ChecklistCodecTests.swift`
**Key changes**:
- `Checklist { id, name, items, destinationListIdentifier: String?, modifiedAt, revision }` — new stored field; add to the memberwise `init` with a defaulted parameter.
- `init(from:)` — `destinationListIdentifier = try container.decodeIfPresent(String.self, forKey: .destinationListIdentifier)` (the `??`-default idiom), so legacy payloads never throw.
- `encode(to:)` — `encode(destinationListIdentifier, forKey:)` unconditionally.
- `CodingKeys` — add `.destinationListIdentifier`.
- No change to `classify()` / `currentVersion = 2`.

**Tests**: `ChecklistCodecTests` — new XCTest cases `decodesV2PayloadWithoutDestinationAsNil`, `destinationSurvivesEnvelopeRoundTrip`, plus `WatchChecklistStoreTests` assertion that `WatchChecklistStore` preserves the field (shared core model, no watch-side work).
**Verify**: `make test-unit` green.

---

## Stage 2: Store mutation — `setDestination`
The store can change the destination with the same revision/`modifiedAt` bookkeeping as
`rename`, and the change persists through load/sync like any other field.

**Files**: `CheckStitch/ChecklistStore.swift`, `CheckStitchTests/ChecklistStoreTests.swift`
**Key changes**:
- `enum SetDestinationOutcome { case updated, notFound }` — modelled on the `rename` outcome enum.
- `func setDestination(_ identifier: String?, for id: UUID) -> SetDestinationOutcome` — `.notFound` guard; on success mutate the checklist, bump `revision` + `modifiedAt`, `scheduleSave()` (text-edit coalescing path), return `.updated`.
- No new load/save path: the existing envelope encoder writes the new field.

**Tests**: `ChecklistStoreTests` — `setDestinationUpdatesRevisionAndPersists` (reload via a second store over the same defaults), `setDestinationClearsToDefaultWithNil`, `setDestinationForUnknownChecklistReturnsNotFound` (sad path).
**Verify**: `make test-unit` green.

---

## Stage 3: Merge — destination follows the checklist winner
A device merge resolves the destination the same way it resolves `name`, so the most recent
editor controls the list.

**Files**: `CheckStitch/ChecklistMerge.swift`, `CheckStitchTests/ChecklistMergeTests.swift`
**Key changes**:
- Checklist-level winner branch (`ChecklistMerge.swift:73-82`) — extend the overwrite set from `name/revision/modifiedAt` to also copy `destinationListIdentifier`.
- No change to tombstone or item-level rules.

**Tests**: `ChecklistMergeTests` — `winnerDestinationOverwritesLoser`, `loserDestinationIsPreservedWhenNonWinning` (sad path: older revision must not leak its destination in).
**Verify**: `make test-unit` green.

---

## Stage 4: Run orchestration seam — pre-validate, then create-or-fail
The run logic becomes a pure, spy-driven state machine with zero EventKit calls: it validates
the destination *before* creating anything, and returns an outcome the caller can act on.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift` (new),
`CheckStitch/ChecklistReminders.swift`, `CheckStitchTests/TestFixtures.swift`,
`CheckStitchTests/ChecklistRemindersTests.swift` (new)
**Key changes**:
- `struct ReminderListOption: Equatable, Identifiable, Sendable { let id: String; let title: String }` — `id` is `EKCalendar.calendarIdentifier`.
- `struct ReminderListsSnapshot: Equatable, Sendable { let options: [ReminderListOption]; let defaultIdentifier: String? }`.
- `enum ReminderRunOutcome: Equatable { case created(count: Int), destinationMissing, permissionDenied, failed(String) }`.
- `@MainActor protocol ReminderDestinationTargeting { func requestAccess() async throws -> Bool; func reminderLists() async throws -> ReminderListsSnapshot; func create(title: String, in list: ReminderListOption) async throws }` — the seam the next stage implements for real.
- `ChecklistReminders.create(from:targeting:) async -> ReminderRunOutcome` (replaces the `Void` version): access gate → `.permissionDenied`; snapshot; resolve `checklist.destinationListIdentifier` against `options`, or `defaultIdentifier` when nil; unresolved (`nil` default or missing id) → `.destinationMissing` **before the loop**; else loop non-blank items, `create(title:in:)`, count successes, any throw → `.failed(message)`.
- `TestFixtures`: `SpyReminderDestination` recording `createdTitles`/`createdListIDs` with injectable `accessGranted`/`lists`/`createError`.

**Tests**: `ChecklistRemindersTests` (Swift Testing, `@MainActor`) — `createsInChosenList`, `nilDestinationUsesDefaultList`, `missingDestinationCreatesNothing` (assert spy received **zero** creates), `missingDefaultCreatesNothing`, `permissionDeniedReturnsDenied`, `blankTitlesAreSkipped`, `saveFailureReturnsFailed`.
**Verify**: `make test-unit` green.

---

## Stage 5: Real EventKit adapter
The seam has a production implementation; the only real-API test is a construction canary
(`EKEventStore`/`EKReminder` dealloc is unsafe to exercise headlessly).

**Files**: `CheckStitch/EventKitReminderDestination.swift` (new),
`CheckStitchTests/EventKitReminderDestinationTests.swift` (new)
**Key changes**:
- `@MainActor final class EventKitReminderDestination: ReminderDestinationTargeting` — initialised with one long-lived injected `EKEventStore` (never per call); `reminderLists()` maps `eventStore.calendars(for: .reminder)` → `options` and `defaultCalendarForNewReminders()?.calendarIdentifier` → `defaultIdentifier`; `create(title:in:)` builds `EKReminder(eventStore:)` and pins `.calendar` to the matched `EKCalendar` (`#if !os(watchOS)` around `save`, matching `EventKitReminderCreator`).
- `ChecklistReminders` keeps its no-argument caller defaulting to a shared adapter instance.

**Tests**: `EventKitReminderDestinationTests` — construction canary only (`sharedTestEventStore`, no API call); identifier-populated/stability check is a **manual device check** (design Open Risk 1).
**Verify**: `make test-unit` + `make build-mac` green; manual: `make run` → run a checklist with an explicit list, confirm the reminder lands in that list in Reminders.app.

---

## Stage 6: Detail-screen destination selector
The user can pick a list on the edit screen, and the choice flows through `setDestination`
into the synced payload.

**Files**: `CheckStitch/ChecklistDetailView.swift`, `CheckStitchTests/` (no new logic suite beyond Stage 2)
**Key changes**:
- New `Section("Destination list")` with a `Picker` (`.tag` rows: first row `nil` labelled "Default (Inbox)", then `ReminderListOption` ids), copying `SettingsView.swift:17`.
- `@State private var reminderLists: [ReminderListOption]`, `@State private var destinationUnavailable = false` — populated in `.onAppear` via `EventKitReminderDestination.reminderLists()`; denied/empty → default-only row + explanatory `Text`, matching decision 5.
- Binding setter calls `store.setDestination(newValue, for: checklistID)` (Stage 2) and ignores `.notFound`.
- No change to the rename-conflict alert; the buffered-name draft is untouched.

**Tests**: manual/UI only — UI smoke stays as-is (`make test-ui` unchanged); verify by `make run` → edit → change list → relaunch, confirm selection persists.
**Verify**: `make test-unit` + `make test-ui` green; manual persistence check.

---

## Stage 7: Run-failure surfacing on the list screen
Running a checklist no longer flashes success when nothing was created; permission denial and
a missing destination both surface as an alert.

**Files**: `CheckStitch/ContentView.swift`
**Key changes**:
- `createReminders(for id:)` — switch on `await ChecklistReminders.create(from:targeting:)`: `.created` → existing `created.insert(id)`; every other case → leave `created` unset and set `@State private var runErrorMessage: String?` (`.destinationMissing` → "That list no longer exists; no reminders were created.", `.permissionDenied` → access message, `.failed(msg)` → `msg`).
- New `.alert("Couldn't create reminders", isPresented: …, presenting: runErrorMessage)` modelled on the rename-conflict alert; keeps the 1 s spinner minimum.

**Tests**: no new automated suite (view-layer state, no testable seam today) — add a `ContentView`-level manual check; noted below as residual risk.
**Verify**: `make test-unit` + `make test-ui` green; manual: delete the chosen list in Reminders.app, run the checklist → alert shown and zero reminders created.

---

## Testing Checkpoints
After Stage 1 (`make test-unit`), 2 (`make test-unit`), 3 (`make test-unit`), 4 (`make test-unit` — all run outcomes covered by `SpyReminderDestination`), 5 (`make test-unit` + `make build-mac` + manual list verification), 6 (`make test-unit` + `make test-ui` + manual persistence), 7 (`make test-unit` + `make test-ui` + manual missing-list run). **Full gate `./scripts/test.sh` must print `gate: ok` before the work is declared done.**

**Cross-cutting note**: Stage 7 is presentational state with no seam today, so it cannot be
asserted by unit tests — the alternative would be extracting the outcome→message mapping into
a small pure helper (testable in Stage 4) and having the view call it; do that if the plan
budgets the extra file.