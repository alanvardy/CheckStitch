# Task

When a user taps "Add Item" on a checklist detail screen, the app currently
creates an item immediately with a hardcoded generic title `"New item"` and
only lets the user rename it afterwards. Change this so that tapping **Add
Item prompts immediately for the item's name** instead of creating an item
with a generic name — the item is only created when the user confirms the
name.

The existing **Duplicate Checklist** flow is the in-file template to mirror: a
button sets a draft-name `@State` slot and flips an `isPresented` flag, then a
`.alert` with a `TextField` shows, and the create happens only on the confirm
button action (see `ChecklistDetailView.swift:88-96`, `:151-163`, draft slots
at `:18-19`).

## Scope

- `CheckStitch/ChecklistDetailView.swift` — replace the direct
  `store.addItem(to: checklistID)` call at `:82` (button at `:78-87`) with
  alert state + an `.alert` containing a `TextField` bound to a new item-name
  draft slot, creating the item only when the user taps the confirm button. Add
  new `@State` slots alongside the existing `isDuplicatePresented` /
  `duplicateDraftName` at `:18-19`.
- `CheckStitch/ChecklistStore.swift` — the `addItem(to:)` method at `:270-276`
  currently stamps `revision: 1` and `save()`s immediately with a generic
  title. Prefer adding a title-carrying create (e.g. `addItem(to:title:)`, or
  adding a `title` parameter — keep the existing signature as an overload if
  needed for compatibility) so the item is created once with the typed name.
  **Do not** create-then-rename: `updateItem` bumps the revision/title clocks
  a second time, which breaks the single-revision-create semantics asserted by
  `testCreateAddAndDuplicateSeedEveryFieldClock`.
- `CheckStitch/Localizable.xcstrings` — add any new alert title / prompt /
  button strings, following the existing entries (note `"Add Item"` already
  exists at `:660-666`; the hardcoded `"New item"` literal has no key and does
  not need one — persisted defaults are intentionally not localized).

No `CheckStitchCore` model change is required (`ChecklistItem.title` is already
a plain stored property with no default needed at call sites). This is the
**only** add-item trigger in the app (ContentView and the watch target have no
add-item path).

## Tests

- `CheckStitch/ChecklistDetailViewTests` — pin the new `@State` slots the same
  way the duplicate flow is pinned (`String(describing:)` contains
  `isDuplicatePresented` / `duplicateDraftName`, see `:25-34`), plus a test
  that no item is created before confirm and the item is created with the typed
  name on confirm.
- `CheckStitch/ChecklistStoreTests` — existing `addItem` tests (counts, item
  order, revision/timestamp seeding) must stay green; add a case that a title
  passed through the new create lands on the created item. None of the ~30
  existing `addItem` call sites pin the `"New item"` literal, so renaming it is
  safe.

Verify with `make test-unit` before the full `bash scripts/test.sh` gate.

## Why SMALL

Localized ~2-3-file UI change in one screen following an existing in-file
pattern (Duplicate Checklist alert-with-TextField); approach known, no
schema/migration, no new subsystem, no human sign-off (the ticket dictates the
behavior), and the test surface is local.

## Key files (from recon)

- `CheckStitch/ChecklistDetailView.swift` — add-item button `:78-87`, duplicate
  alert template `:88-96`/`:151-163`, state slots `:18-19`.
- `CheckStitch/ChecklistStore.swift` — `addItem(to:)` `:270-276`; do a
  title-carrying create (avoid double revision bump).
- `CheckStitch/Localizable.xcstrings` — new strings; `"Add Item"` at `:660-666`.
- `CheckStitch/ItemEditView.swift` — existing title-edit precedent `:20-28`/`:40-48`.
- `CheckStitchTests/ChecklistDetailViewTests.swift` — state-slot pinning pattern `:25-34`.
- `CheckStitchTests/ChecklistStoreTests.swift` — add-item tests (e.g. `:71-87`,
  `:402-425`, `:494-519`, `:927-938`).
