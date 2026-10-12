# Structure Outline

## Approach

Replace `Checklist.destinationListIdentifier: String?` with a typed
`ChecklistDestination` (`.systemDefault` / `.list(id)` / `.prompt`) encoded under
a new `destination` key, bump `ChecklistCodec.currentVersion` 5 → 6 with a v5→v6
migration, and thread an optional destination override through the single run
funnel so `prompt` resolves at Run time in the sheet, the intent, the widget
deep-link, and the watch reply. The enum swap is a genuinely horizontal schema
change (it touches every call site), so it lands as its own green phase; every
phase after it is a vertical capability end to end.

---

## Phase 0: Horizontal prerequisite — `ChecklistDestination` model + codec v6

No user-visible change; the tree stays green and sync/export/idempotence tests
prove the schema. This phase cannot be vertical: the enum replaces the persisted
field at every call site (model, codec, store, merge, export, funnel, UI), and no
single vertical path can land while the type is half-converted.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`ChecklistCodec.swift`, `ChecklistMerge.swift`, `ChecklistStore.swift`,
`ChecklistSyncService.swift`, `ChecklistReminders.swift` (resolve only),
`CheckStitch/ChecklistDetailView.swift` (binding, two rows preserved)

**Key changes**:
- `enum ChecklistDestination: Codable, Equatable, Hashable { case systemDefault, list(String), prompt }` — new; custom `Codable` (`"systemDefault"`/`"prompt"`, `{"list":"<id>"}`).
- `Checklist.destination: ChecklistDestination` — replaces `destinationListIdentifier: String?`; `CodingKeys.destination`; `decodeIfPresent` tolerant, unconditional encode.
- `ChecklistCodec.currentVersion: Int = 6`; `classify` → `.migratable(from: 1...5)`; v5→v6 migration maps `nil → .systemDefault`, `String(id) → .list(id)`; remote branch in `ChecklistSyncService.reconcileNow`.
- `ChecklistStore.setDestination(_ destination: ChecklistDestination, for:)`; `duplicate`/`freshCopy`/`importInsert` copy the enum.
- `ChecklistMerge`: copy `remoteChecklist.destination` on winner.
- All remaining call sites converted mechanically (no `String?` accessor, no sentinel).

**Contract**: `ChecklistDestination` (public, `Equatable`, `Hashable`, `Codable`),
`Checklist.destination`, `ChecklistCodec.currentVersion == 6`,
`.migratable(from: 1...5)`, `ChecklistStore.setDestination(_:for:)`. Imported,
exported, and synced bytes carry the new `destination` key.

**Tests**: `ChecklistCodecTests.swift` (v5→v6 migration, absent key → `.systemDefault`, round-trip all three cases, version gate rejects v5 bytes), `ChecklistStoreTests.swift` (`setDestination`, duplicate/import preserve prompt), `ChecklistMergeTests.swift` (winner carries `.prompt`, idempotence `merged != envelope`), `ChecklistExportTests.swift` / `ChecklistImportSessionTests.swift` (export→import preserves `.prompt`), `ChecklistSyncServiceTests.swift` (remote v5 migration, `canAcceptRemoteChanges`).

**Verify**: `make test-unit` passes for the codec/store/merge/export/sync suites; `make build` clean (no `String?` leftovers).

---

## Phase 1: Walking skeleton — app prompt end to end

A user can mark a checklist "Ask me each time" in the detail picker, tap Run, pick
a list from the app sheet, and have reminders created in that list exactly once —
without the choice being persisted. Green tests prove the picker writes `.prompt`,
the funnel short-circuits to `.destinationRequired`, the sheet resolves a list and
completes the run.

**Files**: `CheckStitchCore/.../ReminderDestinationTargeting.swift` (outcome),
`ChecklistReminders.swift` (funnel override),
`CheckStitch/ChecklistRunViewModel.swift`, `CheckStitch/ContentView.swift`,
`CheckStitch/DestinationPromptSheet.swift` (new; no `project.pbxproj` edit),
`CheckStitch/ChecklistDetailView.swift` (third row),
`CheckStitch/Localizable.xcstrings` + `CheckStitchTests/LocalizationFixtures.swift`

**Key changes**:
- `ChecklistReminders.create(from:targeting:gate:multipleOverride:destination: ChecklistDestination?)` — when `checklist.destination == .prompt` and `destination == nil` → return `.destinationRequired` before resolve; else resolve `.list`/`.systemDefault` as today.
- `ReminderRunOutcome.destinationRequired` — new case (+ `errorMessage` text).
- `DestinationPromptSheet(options: ReminderListsSnapshot.selectableOptions + default, onRun:, onCancel:)` — new view; requests Reminders access on appear, dismisses + routes `.permissionDenied` on denial.
- `ChecklistRunViewModel`: `destinationPrompt: Checklist?` published; `createReminders(for:)` maps `.destinationRequired` → present sheet; `run(_:in:)` calls the funnel with `.list(id)`; nothing written back to the store.
- `ChecklistDetailView` picker gains an "Ask me each time" row writing `.prompt`; `destinationIsStale` applies only to `.list`.
- New App-catalog keys (6 languages): sheet title, "Ask me each time", default row.

**Contract**: funnel `destination:` parameter and `.destinationRequired` outcome;
`DestinationPromptSheet` + the run-VM/`ContentView` presentation entry point
(consumed by Phase 3's deep-link); `ReminderListsSnapshot.selectableOptions` is
the shared option model.

**Tests**: `ChecklistRemindersTests.swift` (happy: prompt + override creates; sad: prompt + nil → `.destinationRequired`; non-prompt unchanged), `ChecklistRunViewModelTests.swift` (`.destinationRequired` presents sheet, `.permissionDenied` on denied), `ReminderListsSnapshotTests.swift`, `LocalizationTests.swift` + `scripts/l10n-check.sh`.

**Verify**: `make test-unit` passes for the funnel/run-VM/snapshot suites; `bash scripts/l10n-check.sh` clean; `make run` — mark a checklist "Ask me each time", Run, confirm the sheet lists lists and the reminder lands in the chosen one.

---

## Phase 2: Intent prompt — Siri & Shortcuts

Running a prompt checklist from Siri or the Shortcuts app asks for the list
through the system parameter prompt (still `openAppWhenRun = false`); where no
presenter exists the intent reports `.destinationRequired` instead of silently
defaulting.

**Files**: `CheckStitchCore/.../ReminderListEntity.swift` (new: `AppEntity` +
`EntityQuery`, modelled on `ChecklistEntity`), `RunChecklistIntent.swift`,
`CheckStitchCore/.../Resources/Localizable.xcstrings` + `LocalizationFixtures.swift`

**Key changes**:
- `struct ReminderListEntity: AppEntity, Identifiable` — `id: String`, `name: String`; synthetic `"default"` = Inbox.
- `struct ReminderListEntityQuery: EntityQuery` — enumerates EventKit lists via the injected destination seam; degrades to synthetic default when unauthorized.
- `RunChecklistIntent.destination: ReminderListEntity?` — `@Parameter`; after the access-status pre-check, `await $destination.requestValue(...)` only when `checklist.destination == .prompt`; pass resolved `.list(id)` to the funnel.
- `RunsChecklistDialogue.destinationRequired` — new dialogue case; nil destination in a headless context → `.destinationRequired`.
- New Core-catalog keys (6 languages).

**Contract**: `ReminderListEntity` / `ReminderListEntityQuery`, the
`RunChecklistIntent.destination` parameter shape, `RunsChecklistDialogue.destinationRequired`.

**Tests**: `RunChecklistIntentTests.swift` (prompt requests the value and uses it; prompt + nil headless → `.destinationRequired`; non-prompt skips prompting), `ChecklistEntityQueryTests.swift` (query enumeration + unauthorized fallback), `LocalizationTests.swift`.

**Verify**: `make test-unit` passes for the intent/entity-query suites; `bash scripts/l10n-check.sh` clean; manual Shortcuts run of a prompt checklist shows the list picker.

---

## Phase 3: Widget hand-off — prompt opens the app

A prompt checklist's widget tile no longer runs headlessly; tapping it opens the
app to the prompt sheet for that checklist.

**Files**: `CheckStitchWidget/SingleChecklistWidget.swift`, `MultiChecklistWidget.swift`,
`CheckStitch/ContentView.swift` (`onOpenURL`)

**Key changes**:
- Prompt checklists set `widgetURL(URL(string: "checkstitch://run?checklist=<id>")!)` and withhold `Button(intent:)`.
- `ContentView.onOpenURL` filters strictly by scheme `checkstitch` + host `run`, reads `checklist=<uuid>`, and routes to the Phase 1 sheet entry point; all other URLs continue to `SharedImportInbox.receive` (fixes the current unfiltered swallow).

**Contract**: URL shape `checkstitch://run?checklist=<uuid>`; the Phase 1 sheet
presentation entry point.

**Tests**: `ChecklistRunViewModelTests.swift` (deep-link → prompt sheet for the id), `SharedImportInboxTests.swift` (non-`checkstitch` URL still imports; malformed `checkstitch://` does not).

**Verify**: `make test-unit` passes for the run-VM/inbox suites; `make widget-build`; `make run` — tap a prompt widget, confirm the sheet appears for that checklist.

---

## Phase 4: Watch reply — "Choose a list on iPhone"

Running a prompt checklist from the watch replies instead of creating; the phone
still owns EventKit and no destination data crosses the boundary.

**Files**: `CheckStitchCore/.../ChecklistSync.swift` (`RunResultKind`),
`CheckStitch/ChecklistSyncCoordinator.swift`,
`CheckStitchWatch/` (copy) + `CheckStitchWatch/Localizable.xcstrings`

**Key changes**:
- `RunResultKind.destinationRequired` — new wire case (name + serialization).
- `ChecklistSyncCoordinator` run handler returns `.destinationRequired` when the checklist is `.prompt` (guarded by the funnel outcome).
- Watch copies the new kind to "Choose a list on iPhone"; new Watch-catalog keys (6 languages).

**Contract**: `RunResultKind.destinationRequired` name/serialization, shared
across the wire.

**Tests**: `ChecklistSyncMessageTests.swift` (wire round-trip of the new kind), `ChecklistSyncCoordinatorTests.swift` (prompt run → `.destinationRequired` reply), `WatchChecklistStoreTests.swift` (run phase), `LocalizationTests.swift`.

**Verify**: `make test-unit` passes for the sync/coordinator/watch suites; `bash scripts/l10n-check.sh` clean; `make watch-build`.

---

## Phase 5: Hardening & edge states

Polish-only slice — the sad paths and access ordering that the earlier green
slices deliberately deferred.

**Files**: `CheckStitchCore/.../ReminderDestinationTargeting.swift`,
`CheckStitch/ChecklistRunViewModel.swift`, `ContentView.swift`, catalogs/fixtures

**Key changes**:
- `ChecklistDestination` equality/idempotence confirmed under merge stress.
- Access ordering in the intent and the sheet: `.notDetermined` prompts, `.denied` routes to the permission-denied error (never an empty list).
- `destinationIsStale` copy only for `.list`; `.prompt` never flagged.
- Empty-options, malformed deep-link, and cross-version (v5 device ↔ v6) messaging covered by tests.

**Contract**: none (behaviour hardening of the existing contracts).

**Tests**: `ChecklistRunViewModelTests.swift`, `ChecklistRemindersTests.swift`, `ReminderListsSnapshotTests.swift`, `ChecklistMergeTests.swift`, `RunChecklistIntentTests.swift` — permission-denied, missing-list, empty-options, version-gate sad paths.

**Verify**: `make test-unit` (all destination/run suites); then the full `./scripts/test.sh` gate prints `gate: ok`.

---

## Testing Checkpoints

- After Phase 0: `make test-unit` green for codec/store/merge/export/sync.
- After Phase 1: `make test-unit` green for funnel/run-VM/snapshot; `l10n-check.sh` clean; app-sheet manual run verified.
- After Phase 2: `make test-unit` green for intent/entity-query; Shortcuts manual prompt verified.
- After Phase 3: run-VM/inbox suites green; `make widget-build`; widget hand-off verified.
- After Phase 4: sync/coordinator/watch suites green; `make watch-build`.
- After Phase 5: full `./scripts/test.sh` → `gate: ok`.
