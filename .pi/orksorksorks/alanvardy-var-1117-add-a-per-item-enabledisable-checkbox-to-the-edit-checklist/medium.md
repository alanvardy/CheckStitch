# Task

Add a durable per-item **enabled/disabled** checkbox to the Items list of the "Edit checklist" screen (`ChecklistDetailView`/`ItemRow`), so a user can keep an item in a checklist but exclude it from a run. The flag lives on `ChecklistItem` (`isEnabled: Bool = true`), is durable, syncs via iCloud, round-trips export/import, and is plumbed through the run, watch, and widget paths.

Decisions are already made (per the ticket) — implement them, don't re-derive:
- **Surface**: one checkbox per row in the Items list of `ChecklistDetailView` (title "Edit checklist"). `ItemEditView` stays unchanged. A **separate leading button outside the `NavigationLink` label**: tapping the box toggles enabled/disabled; tapping the rest of the row pushes `ItemEditView`. Accessibility id `itemEnabledToggle-<uuid>`. Row template is uniform — the checkbox shows on **every row, including blank/placeholder ones**.
- **Appearance**: disabled row dims title+description to `.secondary`; **no strikethrough** (app never marks items complete).
- **Model** (`Checklist.swift`): add `ChecklistItem.isEnabled: Bool = true`, plus per-field sync clocks `enabledRevision` / `enabledModifiedAt` (seeded from the coarse clock, `decodeIfPresent … ?? true`, encoded unconditionally); seed those clocks in `migrated(at:)`. Additive Bool → **no envelope bump**, `ChecklistCodec.currentVersion` stays 5 (same precedent as `prefixesReminderNumbers`).
- **Merge** (`ChecklistMerge.swift`): LWW branch for `isEnabled` in `mergedItems`; include `enabledRevision` in the coarse high-water `max(...)` so the tombstone invariant holds.
- **Store** (`ChecklistStore.swift`): `updateItem(checklistID:itemID:isEnabled:)` — no-op on unchanged value, bump `revision`, stamp `enabledRevision`/`enabledModifiedAt`, debounced save. `addItem` defaults to enabled.
- **Run** (`ChecklistReminders.swift`, `ChecklistCreator.swift`): filter `!isBlank && isEnabled` in the create loop, the `itemCount` used for numbering (keeps `1…n` contiguous over enabled, non-blank items), and the `partiallyCreated` total. A disabled item produces **no reminder**.
- **Zero enabled items**: run affordance disabled on **phone, watch and widget**. `ChecklistWidgetDisplayModel` refuses to run when zero enabled (non-blank) items, not only on Reminders access. The all-blank edge case keeps current zero-created behaviour; free-run slot never consumed (already released when `created == 0`).
- **Watch**: `WatchChecklistViewModel.visibleItems` **hides disabled items**, extending the existing "blank rows never run, so they are hidden" rule.
- **Export/import**: disabled items are **kept** with the flag intact (file round-trips exactly); restored on import.
- **Platforms**: iPhone, iPad and macOS (shared view), always visible; no dependency on iOS `EditButton`.
- **Bulk**: per-item only — **no bulk enable/disable** in scope.
- **Localization**: prefer reusing existing keys (glyph + accessibility label); any new key needs all 6 languages + a `LocalizationFixtures.requiredKeys` entry.

## Why MEDIUM

Broad (M3): MULTI_MODULE + CROSS_CUTTING (known ordering) — model/merge/store/run in `CheckStitchCore`; UI in `CheckStitch/ChecklistDetailView.swift` (ItemRow, run-button gating); plus watch (`WatchChecklistViewModel`), widget (`ChecklistWidgetDisplayModel`), export/import codec, localization, and multiple test suites — well over a dozen files across core + app + watch + widget + tests. M1/M2 hold: the additive Bool + per-field-clock change has an exact precedent (`prefixesReminderNumbers`: no envelope bump, `decodeIfPresent ?? true`, no backfill/reformat) and all design decisions/trade-offs are already settled in the ticket — approach known, no schema/design sign-off.

## Key files

- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` (model + `enabledRevision`/`enabledModifiedAt` clocks, `migrated(at:)`, `ChecklistCodec` — version stays 5)
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift` (LWW for `isEnabled`, coarse high-water includes `enabledRevision`)
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift` (`updateItem(checklistID:itemID:isEnabled:)`, `addItem` default enabled)
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistReminders.swift` + `ChecklistCreator.swift` (run filter `!isBlank && isEnabled`, numbering `itemCount`, `partiallyCreated`)
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift` + `ChecklistEntity.swift` (export/import keep flag)
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidgetDisplayModel.swift` (zero-enabled runnable gate)
- `CheckStitchCore/Sources/CheckStitchCore/WatchChecklistViewModel.swift` (watch `visibleItems` hides disabled)
- `CheckStitch/ChecklistDetailView.swift` (ItemRow checkbox + dimming, run-button gating)
- `CheckStitch/ChecklistRunViewModel.swift` (zero-enabled gating on the phone list row)
- Tests: `ChecklistCodecTests`, `ChecklistMergeTests`, `ChecklistStoreTests`, `ChecklistRemindersTests`/`ChecklistCreatorTests`, `ChecklistDetailViewTests`, `ChecklistWidgetDisplayModelTests`, `WatchChecklistStoreTests`, `LocalizationFixtures`; fixtures in `CheckStitchTests/TestFixtures.swift`.

Gate: `make test-unit`, then `./scripts/test.sh` prints `gate: ok`.