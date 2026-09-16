# Design Discussion

## Current State

`ChecklistItem` (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:8`) is
the canonical synced record: `id`, `title`, `description`, `modifiedAt`,
`revision`, `relativeDate: Int?`, and **six per-field sync clocks**
(`titleRevision/titleModifiedAt`, `description*`, `relativeDate*`,
`:41-52`). Every editable field is a value + `fieldRevision`/`fieldModifiedAt`
pair. The init (`:9-30`) seeds an unspecified field clock from the coarse clock
("a legacy payload attributes its last whole-item edit to every field").

Codec (`:67-115`): `CodingKeys` lists all keys; `id`/`title` are required; every
other key is `decodeIfPresent` with a fallback (`description ?? ""`,
`modifiedAt ?? .distantPast`, `revision ?? 0`), and `encode(to:)` writes **every**
key unconditionally — `relativeDate` is written explicitly via
`encodeNil(forKey:)`/`encode` because the `Int?` overload may omit it
(`:101-108`). `relativeDate` is the canonical *additive optional field with no
version bump*: it landed between v3 and v4, an absent key decodes fine, and
`ChecklistCodecTests.swift:171` pins that a v4 payload without the key stays
`.loaded`. `classify` treats only whole-key absence as tolerant — a
wrong-typed value makes the payload `.unreadable`
(`ChecklistCodecTests.swift:187`).

Store mutators (`CheckStitch/ChecklistStore.swift`) stamp the coarse clock plus
the edited field's clock: `updateItem(title:)` `:286-296`,
`updateItemDescription` `:302-312`, `updateItem(relativeDate:)` `:319-330` — the
last one carries a **no-op guard** (`:321`) so re-committing an identical value
never wins a spurious LWW round. All three use debounced `scheduleSave()`; the
structural ops (add/remove/move/delete/duplicate/import) call `save()` directly
(`:333,:366,:378`).

Merge (`CheckStitch/ChecklistMerge.swift:116-171`) copies a shared item **per
axis** — coarse clock, then each field's clock pair — and clamps the coarse clock
to the high-water `max` over all field revisions (`:160-163`) so the tombstone
invariant (`removed.revision + 1`, `ChecklistStore.swift:333`) still dominates.
`wins` (`:198-203`) is revision → date → smaller deviceID. Order reconciles
separately via `orderRevision` (`:86-90`), and `store.apply(remote:)`
(`ChecklistStore.swift:390`) folds a merge in behind an idempotence guard.

The item screen `ItemEditView` (`CheckStitch/ItemEditView.swift:12-124`) is a
bare `Form` with three sections: `Section("Title")`
(`itemEditTitleField`, `:22-25`), `Section("Description")`
(`itemEditDescriptionField`, `:27-30`), and a `Section` with header "Due date" +
footer copy hosting `dueDateField` (`:32-38`, `:102-113`). Bindings re-find the
item from the store on every read/write; iCloud edits land live via
`.onChange(of: item.relativeDate)` (`:57-63`); `.onDisappear` flushes the
debounce (`:67`). The screen is reachable only from the whole-row
`NavigationLink` `ItemRow` (`ChecklistDetailView.swift:271-289`).

Reminder creation at runtime goes through
`ChecklistReminders.create(from:)` → `ReminderDestinationTargeting.create(title:
notes:in:dueDateComponents:)` (`CheckStitch/ChecklistReminders.swift:16-45`,
protocol `ReminderDestinationTargeting.swift:87`), implemented by
`EventKitReminderDestination` (`CheckStitch/EventKitReminderDestination.swift:31-52`),
which builds an `EKReminder`, sets `title`/`notes`/`calendar`/`dueDateComponents`
and saves. `EKReminder.priority` is **never set today**. A second, parallel seam
(`ReminderCreating` `CheckStitchCore/.../ReminderCreating.swift:9-38`,
`ChecklistCreator.swift:27`, `ChecklistViewModel`) is exercised only by tests —
the app no longer routes through it.

The UI has no popover precedent; value picking is `Picker` + `.tag` +
accessibility identifier inside a `Form` section
(`SettingsView.swift:21`, `ChecklistDetailView.swift:50`), and small panels are
`.alert`/`.confirmationDialog`/`.sheet`.

## Desired End State

Every `ChecklistItem` carries a priority: `none` (default), `low`, `medium`, or
`high`. In `ItemEditView` a new `Section("Priority")` row shows the current
priority on the right, with an info-button/menu control opening an overlay menu
of the four options; picking one persists immediately through a new store
mutator. Priority survives: codec round-trip (key always written, absent key →
`.none`), KV persistence and reload, iCloud merge as an independent axis with a
per-field clock, duplicate/import/export (through the same codec), and running a
checklist — the created `EKReminder` gets the matching `priority`
(`none→0, low→9, medium→5, high→1`, EventKit's own scale).

Verification: `make test-unit` covers the new model/mutator/merge/codec cases;
`bash scripts/test.sh` (gate: `make build` → pinned-sim pre-boot → `make test` →
`make build-mac` → `make watch-build` → `scripts/tests/run.sh` → shellcheck →
`gate: ok`) proves all four platform legs compile. Static evidence is
insufficient for the *visible* outcome — the final check is the installed
simulator/device bundle showing the priority row and menu (see `devicectl`).

## Patterns to Follow

- **Per-field clock triple** — `Checklist.swift:41-52` + `ChecklistStore.swift:286-330`
  is the template for a new persisted field: add `priority`,
  `priorityRevision: Int`, `priorityModifiedAt: Date`; seed the clocks from the
  coarse clock in the init (`:22-29`); stamp both plus `revision += 1` in the
  mutator.
- **No-op guard on discrete writes** — copy `updateItem(relativeDate:)`'s
  `guard item.relativeDate != relativeDate` (`ChecklistStore.swift:321`) so
  re-selecting the current priority does not bump revisions.
- **Additive field, no version bump** — mirror `relativeDate`'s decode
  (`Checklist.swift:84-91`) and the unconditional-write encode (`:101-108`).
  Priority is non-optional so no `encodeNil` dance is needed, but the key is
  still written every time.
- **Merge as an independent axis** — add a `priorityRevision`/`priorityModifiedAt`
  comparison block beside `ChecklistMerge.swift:147-152` and include
  `priorityRevision` in the high-water `max` (`:160-163`).
- **Form-section UI** — `ItemEditView.swift:32-38`/`:102-113` is the section
  shape (header + footer copy + control); identifiers follow
  `itemEdit<Title>Field` (`:23,:29,:107`). New control →
  `itemEditPriorityMenu`/`itemEditPriorityRow` in that family. Show the label
  with `Text` (never `LocalizedStringKey`-wrapping an enum-derived string).
- **Test-double update, not test-only divergence** — extend
  `RecordingReminderDestination` (`CheckStitchTests/TestFixtures.swift:73-84`)
  with a `createdPriorities` recorder alongside `createdDates`.
- **Swift Testing for new suites/cases** — `struct <Thing>Tests`, behaviour-named
  functions, `@Test(arguments:)`; the three XCTest codec/store/export files keep
  the `.loaded`/`classify` regression style they already use
  (`ChecklistCodecTests.swift:253`). Add `@MainActor` only where EventKit/store,
  which the existing suites already do.

Patterns found in research that must **not** be followed:

- **Do not** add a version bump / migration branch to `classify`
  (`Checklist.swift:425-445` region). `relativeDate` is the precedent; a v5 bump
  would invalidate the existing v1/v2/v3 classification regression for no gain.
- **Do not** make `priority` a free-form `Int` 0–9. The enum is what makes the
  menu exhaustive, the tests meaningful, and the EventKit mapping total.
- **Do not** restructure `ItemRow` (`ChecklistDetailView.swift:271-289`) into an
  `HStack` with a nested info button: the whole row is a `NavigationLink` and iOS
  drops taps on controls nested in a link label. The priority control lives in
  `ItemEditView` (Q1B).
- **Do not** route the write through the coarse `revision` only — that breaks
  the "title edit and priority edit are independent" property the model exists
  to provide.

## Design Decisions

1. **Control lives in `ItemEditView`, not on `ItemRow`** — the ticket's "each
   item row" wording conflicts with `ItemEditView` rendering a single item;
   `ChecklistDetailView`'s rows are whole-row navigation links, so a nested
   button would be unreliable. A `Section("Priority")` in the item Form has no
   such conflict and keeps `ItemRow`'s layout/animation untouched.
2. **`public enum ChecklistItemPriority: Int, Codable, CaseIterable, Hashable, Sendable`**
   in a new core file `ChecklistItemPriority.swift`, declared in display order
   `none = 0, low = 9, medium = 5, high = 1` — `allCases` is the menu order and
   `rawValue` is written straight into `EKReminder.priority`, so the mapping is
   total and switch-free. Decoding stays strict (`init(from:)` on the raw value);
   an unknown raw value makes the payload `.unreadable`, consistent with
   `ChecklistCodecTests.swift:187`.
3. **Field + two clocks on the model** — `var priority: ChecklistItemPriority`
   (non-optional, decode-absent → `.none`), plus `priorityRevision`/
   `priorityModifiedAt` seeded from the coarse clock. Chosen over a clock-less
   field so a concurrent title edit and priority edit both survive a merge.
4. **New mutator `updateItem(checklistID:itemID:priority:)`** in
   `ChecklistStore.swift`, shaped exactly like the `relativeDate` overload
   (`:319-330`): no-op guard, coarse + field clock stamp, `scheduleSave()`. A
   debounced save is correct here — the menu is a discrete tap and the view
   flushes on disappear.
5. **Priority reaches the reminder** — add a `priority:` parameter to
   `ReminderDestinationTargeting.create(...)` (`ReminderDestinationTargeting.swift:87`),
   its conformances (`EventKitReminderDestination.swift:31`,
   `TestFixtures.swift:73`), and the call site (`ChecklistReminders.swift:30-34`),
   setting `reminder.priority = priority.rawValue` before the save. Test-double
   records it.
6. **No version bump** — priority is another additive key: absent → `.none`,
   encoder always writes it, and the v1/v2/v3/v4 classification regression must
   be extended rather than altered.
7. **No overlay primitive precedent, so a `Menu`** — anchored on an info-button
   label in the priority row, listing the four options with a checkmark on the
   current one. It is the lowest-risk "overlay" (no new presentation state, no
   `popover`-on-iPhone adaptation question) and mirrors the existing
   picker-with-tags idiom's intent without a pushed screen.

## What We're NOT Doing

- No change to `ItemRow`/`ChecklistDetailView` layout, and no priority badge in
  the checklist list.
- No priority on `Checklist` itself — items only.
- No reordering/sorting items by priority.
- No other `EKReminder` fields (notes, alarms, recurrence) beyond setting
  `priority`; `notes` behaviour stays as-is.
- No v5 envelope, no migration restamp logic, no changes to `classify`.
- No routing the legacy core seam (`ReminderCreating`, `ChecklistCreator`,
  `ChecklistViewModel`) through priority — it is unreachable from the app. Note
  this explicitly in the PR so a reviewer can judge it.
- No localization work beyond reusing existing patterns; no new accessibility
  choreography beyond one identifier per new control.
- No change to save cadence for the existing text fields.

## Open Risks

- **`Checklist.migrated(at:)` (`Checklist.swift:200-230`) must stamp the new
  clocks.** If it constructs items with explicit clock arguments, priority's two
  clocks need adding; if it relies on the init's seeding, this is free. Verify
  with a v1-payload test asserting `priorityRevision == revision`.
- **Strict enum decoding is a one-way door.** A future priority value from a
  newer build on the same iCloud account would make the whole payload
  `.unreadable`. Accepted for consistency with the wrong-type invariant, but if
  tolerance is preferred later it must be a deliberate custom `init(from:)`.
- **Two reminder seams could drift.** Adding `priority` only to
  `ReminderDestinationTargeting` widens the gap with the core `ReminderCreating`
  path; if that path is revived, priority would silently be dropped.
- **`Menu` inside a `Form` row** is the one API with no in-repo precedent — the
  compiler is the oracle (`make build`), and the rendered label/value layout on
  iOS vs the macOS-hosted unit leg may differ; `ViewRenderTests`/
  `ChecklistDetailViewTests` string assertions are the cross-platform guard.
- **Test double breadth**: every conformance of `ReminderDestinationTargeting`
  must be updated in the same commit, or the unit leg fails to compile — check
  the watch target's usage too (`make watch-build`).
