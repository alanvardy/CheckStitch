# Task

In the edit-checklist screen (`CheckStitch/ChecklistDetailView.swift`), add a
button labelled "Duplicate Checklist" directly **above** the existing "Remove
Checklist" button, following the same Button/Label/`accessibilityIdentifier`/
`.checkStitchButton()` idiom used for the buttons in that screen's trailing
`Section`. Pressing it creates a new checklist that is a copy of the current
one — same items (each a fresh `ChecklistItem` with a **new** `UUID`/revision,
never reused IDs) — named `"<original name> copy"` (e.g. "Groceries copy"),
with `uniqueName` disambiguation ("Groceries copy", "Groceries copy 2", …)
handled by the existing naming machinery, persisted through the store's normal
`save()` → `onChange` → sync path so it reaches the same "CheckStitch"
reminders list via iCloud KVS.

Scope and shape, per recon:
- **`CheckStitch/ChecklistStore.swift`** — add a store method (e.g.
  `duplicate(id:)`) that builds the checklist from the source's items with
  fresh UUIDs/revisions, names it via the existing `uniqueName`
  machinery (same path `create(name:)` uses), appends, saves. No schema or
  envelope-version change (stays version 2); no tombstones involved.
- **`CheckStitch/ChecklistDetailView.swift`** — the new button above "Remove
  Checklist" (lines ~37–55), wired to the new store method, with the same
  confirmation/alert conventions as the surrounding actions.
- **`CheckStitch/Localizable.xcstrings`** — new user-facing key(s)
  ("Duplicate Checklist", any "<original> copy" format key) following the
  catalog's conventions: alphabetical JSON, `extractionState: "manual"`, all
  6 languages (`en, de, es, fr, ja, zh-Hans`) with `state: "translated"`.
- **`CheckStitchTests/LocalizationFixtures.swift`** — register the new
  key(s) in the `"App"` `requiredKeys` array (alphabetical order).

No EventKit path involved — no `NSReminders*UsageDescription` changes, no
entitlement changes; macOS and iOS share `ChecklistDetailView` so the button
renders on both; `CheckStitchWatch/` is read-only for checklists and needs no
change.

Tests: store-level duplicate/naming/persistence cases in
`CheckStitchTests/ChecklistStoreTests.swift` (XCTest, `@testable import
CheckStitch`, `makeStore(defaults:)` pattern), the view button wiring in
`CheckStitchTests/ChecklistDetailViewTests.swift` (Swift Testing, pins state
slots via `String(describing:)`), and the localization keys auto-verified by
`LocalizationTests.swift`. Verify with `make test-unit` (fast) before the full
`bash scripts/test.sh` gate.

## Why MEDIUM

MULTI_MODULE + CROSS_CUTTING (known ordering): the change touches the store,
the edit view, the localization catalog and its fixtures, plus 2–3 test
suites (~6 files across the app target and test suite), but the approach is
fully known — mirror the existing `create`/`uniqueName`/`save` pattern with
fresh UUIDs — so no design step or research fan-out is needed (M1–M2 hold).

## Key files

- `CheckStitch/ChecklistDetailView.swift` — new button above "Remove
  Checklist", Section lines ~37–55, `.accessibilityIdentifier("removeChecklistButton")`
  idiom to match.
- `CheckStitch/ChecklistStore.swift` — `create(name:)` (~lines 70–78),
  `uniqueName` (~86–103), `addItem` (~105–108), `save()`/`onChange` sync.
- `CheckStitch/Localizable.xcstrings` — manual alphabetical catalog, 6
  languages.
- `CheckStitchTests/LocalizationFixtures.swift` — `"App"` `requiredKeys`.
- `CheckStitchTests/ChecklistStoreTests.swift` and
  `CheckStitchTests/ChecklistDetailViewTests.swift` — store and view test
  homes (`makeDefaults()`/`makeStore(defaults:)`, `@MainActor` where the view
  is pinned).