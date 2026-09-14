# Design Discussion

VAR-999 — optional free-text description on each `ChecklistItem`, persisted
through the shared envelope codec, editable on iOS, visible on watchOS, and
carried into created reminders as `EKReminder.notes`.

## Current State

- `ChecklistItem` is a four-field `struct` with a hand-written `Codable`
  implemented on the struct itself: `id`/`title` required, `modifiedAt`/
  `revision` optional on decode (`CheckStitchCore/.../Checklist.swift:8-42`).
  `isBlank` is *derived* from `title`, never stored/serialized (`:22-24`).
- **Additive-optional-field idiom is established.** Every sync field decodes
  via `decodeIfPresent` + `??` default (`Checklist.swift:33-34`, `:73-75`,
  `:140-147`); unknown JSON keys are silently ignored by the fixed keyed
  container. The most recent precedent is VAR-991's
  `destinationListIdentifier: String?`, added with `decodeIfPresent` and
  **no version bump** (`origin/main:Checklist.swift:84,100`).
- Payload versions are classified by `ChecklistCodec.classify`
  (`.loaded` / `.migratable` / `.unsupportedVersion` / `.unreadable`), and the
  store refuses to overwrite an unsupported payload (`ChecklistStore.swift:44-77`,
  guard at `:278-281`). On this branch `currentVersion == 2`; **`origin/main`
  already has VAR-995's v3** (`itemOrder`/`orderRevision`/`orderModifiedAt`)
  and VAR-991's destination field, and this branch is 22 commits behind.
- Store item ops: `addItem` stamps `revision: 1`, `updateItem(...title:)`
  bumps `revision`/`modifiedAt` and debounces via `scheduleSave()`
  (`ChecklistStore.swift:184-198`, `:252-271`); `duplicate` copies **only
  `title`** into fresh-id items (`:142`); item ops never touch the checklist's
  own `revision`/`modifiedAt` (`Checklist.swift:43-50`).
- Merge is **whole-item last-write-wins**: a winning remote item replaces the
  local struct wholesale (`ChecklistMerge.swift:110`) — no field-level merge
  exists anywhere.
- Reminder creation: the production path is `ChecklistReminders.create` via the
  `ReminderDestinationTargeting` seam (`origin/main:ReminderDestinationTargeting.swift:83`,
  `EventKitReminderDestination.swift:30-40`), which sets `reminder.title` and
  nothing else. The core `ChecklistCreator`/`ReminderCreating` seam is
  test-only and also title-only.
- iOS editor: `ChecklistDetailView` renders one `TextField("Item", text:)` per
  row bound through `titleBinding(...)`, which mutates the store **per
  keystroke** (`ChecklistDetailView.swift:63-65`, `:188-193`).
- watchOS: `WatchChecklistDetailView` renders a read-only single-line
  `Text(item.title)` per row, filtered by `!item.isBlank`
  (`WatchChecklistDetailView.swift:11-18`). `WatchChecklistStore` only accepts
  `.loaded` envelopes from WCSession context (`ChecklistSync.swift:106-114`).

## Desired End State

A checklist item carries an optional description that survives every hop of
the lifecycle and never affects existing behaviour:

- **Model/codec**: `ChecklistItem` gains `public var description: String`,
  defaulting to `""`, decoded with `decodeIfPresent(.description) ?? ""`
  (absent key ⇒ empty) and encoded unconditionally. Existing v3 item JSON
  decodes unchanged; newly written JSON gains one `"description"` key.
- **Persistence/sync**: round-trips through the App-Group UserDefaults
  `checklists.v1` envelope, iCloud KVS, and WCSession context bytes without
  any codec/version change (no bump; stays at v3 post-rebase).
- **Merge**: a description edit on one device wins/loses with the whole item
  under existing LWW rules — no merge changes required.
- **Store**: a description edit bumps the item's `revision`/`modifiedAt` and
  debounces; `duplicate` carries each source item's description forward.
- **iOS**: each Items row has a multi-line description field under the title,
  persisted per keystroke.
- **watchOS**: each visible row shows the description as a secondary caption
  line when non-empty.
- **Reminders**: `EKReminder.notes` is set to the item's description when
  non-empty (in addition to `title`); blank descriptions leave `notes` nil.

**Verification**: `make test-unit` (fast) then the full gate
`bash scripts/test.sh` prints `gate: ok`. Unit proof: an item JSON without a
description decodes to `""`; a store edit/duplicate round-trips the
description; the destination adapter's fake receives the notes; the watch
store's context decode preserves it.

## Patterns to Follow

- **Optional-field codec idiom** — add a `CodingKey`, encode
  unconditionally, `decodeIfPresent(...) ?? ""` (`Checklist.swift:27-42`).
  Copy VAR-991's `destinationListIdentifier` handling on `origin/main` rather
  than inventing a new shape.
- **Per-keystroke item binding + debounced save** — model the description
  binding on `titleBinding` (`ChecklistDetailView.swift:188-193`) and route it
  through `scheduleSave()` (300 ms coalescing, `ChecklistStore.swift:252-271`),
  not the structural `save()`.
- **Mutation contract** — item edits set `revision += 1` and
  `modifiedAt = now()` only; never the checklist's `revision`/`modifiedAt`
  (`ChecklistStore.swift:190-198`, `Checklist.swift:43-50`).
- **Whole-item LWW** — rely on `ChecklistMerge.swift:110`; do **not** add
  field-level merge logic for the description.
- **`isBlank` stays title-derived** — do not let a non-empty description make
  a blank title survive (`Checklist.swift:22-24`,
  `WatchChecklistDetailView.swift:11-14`).
- **Test style** — `struct <Thing>Tests`, behaviour-named functions,
  `@Test(arguments:)`, `#expect`, `@MainActor` on suites touching EventKit;
  fixtures via `makeItem` in `TestFixtures.swift` (conventions.md).
- **Do NOT follow**: the unconditional `try container.encode(...)` for
  *required* fields is fine, but do not switch `id`/`title` to optional; and do
  not bump `currentVersion` (see Decisions).
- **Do NOT follow**: do not extend the inert core `ChecklistCreator` seam in
  this ticket (see "What We're NOT Doing").

## Design Decisions

1. **No version bump — stay at v3 post-rebase.** A description is a purely
   additive optional field; the `destinationListIdentifier` precedent
   (`origin/main:Checklist.swift:84,100`) proves the project's convention is to
   add `decodeIfPresent` fields without a bump. Bumping to v4 would make every
   older build `.unsupportedVersion`, freezing *all* their checklist edits and
   making the watch ignore the payload entirely (`ChecklistSync.swift:106-114`).
   Accepted cost: an older v3 build silently drops descriptions on its next
   save; the guard does not protect an *unknowable* field.
2. **Description is a non-optional `String` defaulting to `""`.** Empty string
   means "no description"; this matches `title`'s shape, keeps the SwiftUI
   binding trivial, and avoids optional-unwrapping at every read. It is
   encoded unconditionally like the other fields.
3. **Description does not affect blankness.** `isBlank` remains a pure
   function of `title`; a blank title is still hidden/never turned into a
   reminder even with a populated description.
4. **Description is stored verbatim — no trimming/normalization.** Matching
   `title`, whitespace is preserved; the UI decides presentation.
5. **Store gets a dedicated `updateItemDescription(checklistID:itemID:description:)`.**
   Changing `updateItem`'s signature would ripple through call sites and tests;
   a sibling mutator mirrors the existing one, bumps `revision`/`modifiedAt`,
   and calls `scheduleSave()`. `addItem` is unchanged (new items start `""`).
6. **`duplicate` copies the description** alongside the title when building
   fresh-id items (`ChecklistStore.swift:142`). This is the one place new item
   construction can silently lose a field.
7. **iOS: second inline field per row** — `TextField("Description", text:,
   axis: .vertical)` under the title inside the existing `Section("Items")`,
   bound per keystroke like `titleBinding`. Smallest change that keeps the
   single-screen editor and matches the established pattern.
8. **watchOS: two-line row** — a `VStack(alignment: .leading)` with the title
   plus a `.font(.caption).foregroundStyle(.secondary)` description line, shown
   only when the description is non-empty; `visibleItems` keeps filtering on
   `isBlank`.
9. **Description flows into reminders as `EKReminder.notes`** through the
   production seam: add a `notes:` (or description) parameter to
   `ReminderDestinationTargeting.create(title:in:)`
   (`origin/main:ReminderDestinationTargeting.swift:83`) and set
   `reminder.notes` in `EventKitReminderDestination.create`
   (`origin/main:EventKitReminderDestination.swift:30-40`) when non-empty.
   Update the in-memory fake/spy used by tests accordingly.
10. **Re-base on `origin/main` as plan step 0.** The branch is v2 and 22
    commits behind main's v3 + destination seam; implementation must start from
    main so the codec version, `itemOrder` self-heal, and the destination
    targeting protocol are present. `ChecklistItem` is untouched by VAR-991/995,
    so the model diff is conflict-free; `ChecklistDetailView` and
    `ChecklistReminders` changed shape and must be edited against main.
11. **Tests ship with the code** — codec absent-key ⇒ `""`, store edit stamping,
    duplicate copy, merge LWW survival, destination-adapter notes, iOS binding
    pin, and watch context round-trip, per the repo's happy+sad-path rule.

## What We're NOT Doing

- **No version bump** and no new `ChecklistCodec` classification case.
- **No field-level merge** — description rides whole-item LWW only.
- **No change to the legacy core `ChecklistCreator` / `ReminderCreating`
  seam.** It is test-only and off every production path; updating it would fork
  the reminder API for no user-visible benefit. The production
  `ReminderDestinationTargeting` path is the one that gets `notes`.
- **No edit of already-created reminders** (the app's core promise) — notes
  are only set at creation time.
- **No description on checklists themselves**, only items.
- **No new versions of existing non-blank items** on load: absent description
  decodes to `""` and is not written back until the item is next saved.
- **No localization/agenda work beyond the new "Description" placeholder key**
  required by the field; no watch-side editing (watch stays read-only).
- **No `isBlank`/validation semantics change** — blank titles remain skipped.

## Open Risks

- **Silent drop by older v3 builds** (accepted with Decision 1): a device on
  current main that has not been updated will overwrite a synced description
  with `""` on its next save. This is inherent to any additive field without a
  version bump; document it in the PR.
- **Rebase surface**: `ChecklistDetailView`/`ChecklistReminders` moved under
  VAR-991; if the rebase is done late, the item-row and reminder-seam edits may
  need rework. Do it first (Decision 10).
- **Reminder-notes protocol churn**: adding a parameter to
  `ReminderDestinationTargeting.create` touches every conformance and fake;
  check `CheckStitchTests` fakes and `CheckStitchCore` tests compile after the
  change.
- **`description` shadows `CustomStringConvertible`-style naming.** It is
  legal Swift and idiomatic for models, but review whether the team prefers
  `details`/`notes`; renaming later is a codec-key change.
- **`decodeIfPresent` on a malformed value** (e.g. `"description": 42`) throws
  and makes the whole payload `.unreadable`; only whole-key absence is
  tolerant. Existing fields share this behaviour, so it is accepted, but a
  test pinning absent-vs-malformed would harden it.
- **Watch row density** on small watch sizes with long descriptions; the
  caption is clamped by SwiftUI's default line limit — verify on device with
  `bash scripts/run-watch.sh`.