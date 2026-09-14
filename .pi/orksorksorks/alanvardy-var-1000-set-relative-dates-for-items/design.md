# Design Discussion

## Current State

CheckStitch items today carry only identity and text state. `ChecklistItem`
(`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:8`) has
`id, title, modifiedAt, revision` with custom `CodingKeys` (`:27`), a lenient
decoder (`decodeIfPresent … ?? default`, `:29-35`) and an encoder that always
writes every key (`:38-41`). The same forgiving decode / eager encode pattern
repeats up the stack: `Checklist` (`:69-82`) and `ChecklistEnvelope`
(`:144-155`). The versioned wire format is `ChecklistCodec` (`:169-221`) with
`currentVersion = 2` (`:169`); `classify` (`:193-208`) accepts exactly 2
(`.loaded`) or legacy 1 (`.migratable`), and everything else is
`.unsupportedVersion` or `.unreadable`. v1→v2 was handled by field defaults plus
`Checklist.migrated(at:)` stamping sync identity (`:89-104`).

An item edit flows UI → store → KVS: `ChecklistDetailView` renders one
`TextField` per item (`CheckStitch/ChecklistDetailView.swift:38`) bound through
`titleBinding` (`:152`), whose `set` forwards each keystroke to
`store.updateItem` (`CheckStitch/ChecklistStore.swift:190`), which bumps
`revision`, stamps `modifiedAt` and calls `scheduleSave()` (300 ms coalescing,
`:252`). `save()` (`:266`) refuses only when `canOverwriteStoredPayload` is
false (`:271`, set in `init` at `:66-79`) and writes
`ChecklistCodec.encode(envelope)` under key `checklists.v1` (`:44`). Sync goes
through `ChecklistSyncService.reconcileNow` (`:132-172`) into
`store.apply(remote:)` (`ChecklistStore.swift:221-238`) and the whole-item LWW
merge in `CheckStitch/ChecklistMerge.swift` (winners by
`revision > modifiedAt > deviceID`, `:126-133`; winning item replaces loser
entirely, `:104-122`). The watch reads the same envelope via
`WatchChecklistStore.receive` (`CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift:119-133`),
which only acts on `.loaded`.

Reminder creation never sets a date: the shipping path
`ChecklistReminders.create` (`CheckStitch/ChecklistReminders.swift:8-22`) builds
a fresh `EKEventStore` and sets only `title` + `calendar` (`:17-18`); the
test-only core mirror (`ReminderCreating.swift:20-42`, `ChecklistCreator.swift:21-30`,
`ChecklistViewModel.swift`) sets the same two fields. CheckStitch contains **no**
calendar/`DateComponents` usage; the reference for date-only due dates is
`/Users/vardy/dev/SingleThread` (`EventKitStoring.makeReminder`,
`ReminderStore.rescheduleReminder`, `Calendar.current.dateComponents([.year,.month,.day], from:)`).

## Desired End State

`ChecklistItem` gains an optional relative-date integer: `0` = today,
`1` = tomorrow, negative = the corresponding day in the past, `nil` = no date.
No time-of-day support. The value:

1. is editable per item in `ChecklistDetailView`, alongside the title;
2. round-trips through `checklists.v1` persistence and iCloud/watch sync
   without loss;
3. causes the reminder created for that item to carry a **date-only**
   `EKReminder.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day], from: today + offset)`;
   items with no offset keep today's no-date behaviour.

Verification: `make test-unit` for the fast loop, `bash scripts/test.sh` as the
gate (`conventions.md`). New unit coverage must pin round-trip, version
classification, LWW, the pure date arithmetic, and both reminder paths.

## Patterns to Follow

- **Lenient decode / eager encode**: add the field to `CodingKeys` and decode
  with `decodeIfPresent(Int.self, forKey: .relativeDate) ?? nil`, mirroring
  `Checklist.swift:29-35`; keep unconditional encoding (`:38-41`).
- **Versioned codec discipline**: extend `ChecklistCodec.classify`
  (`Checklist.swift:193-208`) following the `case 1 → .migratable` precedent,
  and use the existing `Outcome` cases (`:173-187`) rather than adding new
  ones.
- **Store mutation shape**: follow `updateItem`
  (`ChecklistStore.swift:190`) — guard both indexes exist, mutate, `revision += 1`,
  `modifiedAt = now()`, `scheduleSave()`; `onChange` still fires only from
  `save()` and not while `isApplyingRemote` (`:266-274`).
- **Pure Core seam for EventKit**: `ReminderCreating`
  (`ReminderCreating.swift:6-10`) and `AppEnvironment` (`Environment.swift:5-10`)
  are the injection pattern; extend them rather than reaching into EventKit from
  tests. `SpyReminderCreator` (`CheckStitchTests/TestFixtures.swift:25-43`) is
  the fake to extend.
- **Swift Testing conventions**: `struct <Thing>Tests`, behaviour-named
  functions, `@Test(arguments:)`, `@MainActor` on anything touching EventKit or
  the view model (`conventions.md`). `ChecklistCodecTests`/`ChecklistStoreTests`
  use the older `func testX` XCTest style — keep each file's existing style.
- **Accessibility ids**: camelCase `<noun>Field`, e.g. a new
  `itemRelativeDateField` consistent with `checklistNameField`
  (`ChecklistDetailView.swift:34`).
- **Two reminder paths must agree**: the shipping `ChecklistReminders.create`
  and the core mirror must produce the same date; the mirror's
  `create(title:)` seam currently cannot express a date.

**Patterns NOT to follow**: the live path's fresh-`EKEventStore()`-per-call
(`ChecklistReminders.swift:9`) contradicts the mandated single long-lived store
(`ReminderCreating.swift:10-12`, `PhoneSyncAdapter.swift:9`) — do not copy the
per-call lifetime into new code. Do not restamp `revision`/`modifiedAt` when
migrating **v2** payloads: unlike v1, v2 already carries sync state, so
re-stamping would manufacture spurious LWW wins (contrast `Checklist.swift:89-104`,
which is correct only for v1). Do not add per-field merge logic: item merge is
whole-item LWW by design (`ChecklistMerge.swift:104-122`).

## Design Decisions

1. **Envelope version**: bump `currentVersion` to **3**; accept 2 via a
   `.migratable(from: 2, …)` case and 1 as today. `ChecklistCodec.classify`
   (`Checklist.swift:193-208`) gains a `case 2` alongside `case 1`. A v2→v3
   migration loads the payload unchanged (the new field decodes to `nil`) and
   re-encodes at v3 — it does **not** stamp revisions. Rationale: whole-item LWW
   means an old client would silently strip `relativeDate`, and the repo's
   stated invariant is never to let a newer payload be overwritten
   (`ChecklistStore.swift:29-31,271`); `.unsupportedVersion` protects the field
   on old clients at the cost of read-only until they update.

2. **Field shape**: `public var relativeDate: Int?` on `ChecklistItem`, wired
   through `CodingKeys`/`init(from:)`/`encode(to:)` (`Checklist.swift:8-46`)
   with no clamping in the model. **Why**: exactly matches the task's "integer
   offset, no times"; a wrapper type buys no behaviour we need.

3. **UI control**: a compact numeric `TextField` beside the item title in the
   `Section("Items")` row (`ChecklistDetailView.swift:36-43`), `.numberPad`,
   empty string ⇒ `nil`, with a new `relativeDateBinding(checklistID:itemID:)`
   alongside `titleBinding` (`:152`) and an `itemRelativeDateField` id.
   **Why**: matches the existing per-row binding convention and keeps the
   tri-state (none / integer) explicit; partial-input handling is confined to
   the binding's parse.

4. **Reminder date computation**: a pure function in `CheckStitchCore`
   (on `ChecklistItem`, e.g. `dueDateComponents(today:calendar:) -> DateComponents?`)
   returning `calendar.dateComponents([.year,.month,.day], from: calendar.date(byAdding: .day, value: relativeDate, to: calendar.startOfDay(for: today))!)`,
   `nil` when `relativeDate == nil`. Both `ChecklistReminders.create` and the
   core mirror call it. **Why**: one testable source of truth for the
   offset→date-only arithmetic, with no EventKit dependency in the test.

5. **Store and seam APIs**: add an overload
   `updateItem(checklistID:itemID:relativeDate:)` (existing `title:` method
   untouched, `ChecklistStore.swift:190`) and extend the mirror seam to
   `create(title:relativeDate:)` (or an item-aware equivalent) so
   `SpyReminderCreator` can assert dates. **Why**: no churn in existing
   call sites/tests; the dormant seam gains date support so the arithmetic is
   exercised through fakes, matching `ChecklistCreatorTests` today.

## What We're NOT Doing

- No time-of-day / datetime due dates; date-only `DateComponents` only.
- No UI change on watchOS (it lists titles only, `ChecklistSync.swift`) beyond
  ensuring it keeps decoding the bumped envelope.
- No new envelope `Outcome` cases, no tombstone GC, no field-level item merge.
- No v2→v3 data loss: v2 payloads are accepted, not rejected.
- No changes to the persisted key name (`checklists.v1`) or the KVS key.
- No clamping/validation service for negative or large offsets.

## Open Risks

- **Watch across versions**: `WatchChecklistStore.receive`
  (`ChecklistSync.swift:119-133`) acts only on `.loaded`. With a v3 bump, a v2
  payload arriving on a v3 watch is `.migratable` and is ignored (prior list
  retained). Decide during planning whether the watch should also accept
  `.migratable`; if not, document it.
- **Old-client read-only UX**: bumping to v3 intentionally degrades pre-update
  clients to read-only (local lock / failed reconcile). Confirm that is
  acceptable versus Option B's silent field loss.
- **Partial numeric input**: an unbuffered binding can transiently parse ""
  or "-" mid-edit; ensure the binding maps unparseable text to `nil` without
  spurious `revision` bumps (compare the store's existing text coalescing,
  `ChecklistStore.swift:252`).
- **Migration semantics**: the v2 branch must re-encode without touching
  `revision`/`modifiedAt`; confirm `ChecklistStore.init` sets
  `canOverwriteStoredPayload = true` for v2 as it does for v1
  (`ChecklistStore.swift:66-79`).
- **Due-date time zone**: `Calendar.current` is device-local
  (`research.md` Q5, SingleThread precedent); a reminder created just before
  local midnight may land a day off if the device time zone changes before
  sync — accepted, but worth a test around `startOfDay`.