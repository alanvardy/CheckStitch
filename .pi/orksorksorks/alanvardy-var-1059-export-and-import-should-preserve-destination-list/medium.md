# Task

CheckStitch (Swift/SwiftUI; `CheckStitch/` thin app target, `CheckStitchCore/`
local SPM package with models/codec/view model). When a user exports a
checklist and imports it elsewhere, the checklist's **destination list** is
not preserved — the imported checklist silently loses its chosen Reminders
list. Fix export/import so the destination list is preserved on the target.

Root cause is already located: the codec already round-trips the field, but the
import path deliberately strips it. In `CheckStitch/ChecklistStore.swift`,
`freshCopy()` (~lines 174–190) drops `Checklist.destinationListIdentifier`
(`String?`, the `EKCalendar.calendarIdentifier`, `nil` = system default) before
both `importInsert` (line ~196) and `importReplace` (line ~214). `duplicate()`
(~line 162) also omits it but is out of scope unless the recipe dictates
otherwise.

The fix must make the imported copy preserve `destinationListIdentifier`, and
handle the edge case where the source-device Reminders list id does not exist /
resolve on the target device. The existing run-path machinery
(`ReminderDestinationTargeting.swift` — `ReminderListsSnapshot.resolve(identifier)`,
`.destinationMissing`; `ChecklistReminders.swift:24-26`) is the natural safety
net; decide with `medium-plan` whether to validate at import time or defer to
first run, keeping consistent with the LWW merge path (`ChecklistMerge.swift:84`).

## Why MEDIUM

Broad but approach known: touches both `CheckStitchCore` and `CheckStitch`
(~8–11 files total) and a wide test surface (4–6 test suites), so MULTI_MODULE
(#7) + BROAD_TEST_SURFACE (#8) apply — but M1/M2 hold: the bug is located, the
codec already carries the field (no version/schema/migration change), no new
subsystem or shared/convention (build scripts) code is touched, and the one
edge-case decision (stale destination handling) follows an existing
`.destinationMissing` pattern.

## Key files (recon)

- `CheckStitch/ChecklistStore.swift` — **root of the bug**: `freshCopy()`
  drops `destinationListIdentifier` (fix here for both import paths).
- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` — `ChecklistEnvelope`/
  `ChecklistCodec` (v4), field already encoded under `destinationListIdentifier`
  (likely no codec change needed).
- `CheckStitch/ChecklistImportSession.swift` — import decode/stage/commit path.
- `CheckStitch/ChecklistImportExportViewModel.swift`, `ChecklistExportDocument.swift`.
- `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift` —
  `resolve()` / `.destinationMissing` reference for stale-id handling;
  `ChecklistMerge.swift:84` merge consistency.
- Tests: `ChecklistStoreTests.swift` (~104, primary), `ChecklistImportSessionTests.swift`,
  `ChecklistExportTests.swift`, `ChecklistImportExportViewModelTests.swift`,
  pos. `ReminderListsSnapshotTests.swift`.

Gate: `./scripts/test.sh`. Verify with `make test-unit` before the full gate.