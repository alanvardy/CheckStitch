# Design Discussion

## Current State

**The model/codec has no destination concept.** `Checklist` is `id / name /
items / modifiedAt / revision` (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:8-19`);
`currentVersion = 2` (`Checklist.swift:169`). Only sync fields fall back with
`??` on decode (item/checklist `modifiedAt`, `revision`, `items`); `id`, `name`,
`title`, `version` are hard `decode` (`Checklist.swift:31-34, 71-75, 145-148,
207`). `classify()` probes `version` first and yields `.loaded` /
`.migratable(from: 1)` / `.unsupportedVersion` / `.unreadable`
(`Checklist.swift:196-209`); a higher-than-working version makes the store
read-only (`CheckStitch/ChecklistStore.swift:70-72, 241-244`). `ChecklistStore`
is "the only encoder" and writes `version: currentVersion` envelopes under
`"checklists.v1"` (`ChecklistStore.swift:85-90`).

**Creation is hard-wired to the system default and reports nothing.**
`ChecklistReminders.create(from:)` (`CheckStitch/ChecklistReminders.swift:10-28`)
builds a fresh `EKEventStore`, requests full access, and pins every reminder to
`eventStore.defaultCalendarForNewReminders()` (`:21`) with per-item
`save(commit: true)` (`:22`). It returns `Void`; permission denial is a silent
bare `return` (`:14-15`) and save errors are only `logger.error`ed (`:25-27`).
The production caller `ContentView.createReminders(for:)`
(`CheckStitch/ContentView.swift:303-319`) then unconditionally marks success, so
the green checkmark flashes even on total failure.

**No enumeration surface exists.** CheckStitch contains no `EKCalendar`,
`calendars(for:)`, or calendar-identifier handling. The parallel core path
(`ReminderCreating.create(title:)`, `CheckStitchCore/.../ReminderCreating.swift:14-17`;
`ChecklistCreator`/`ChecklistCreationOutcome`, `ChecklistCreator.swift:5-11`)
models `created(count:) / permissionDenied / failed(String)` but has **no
production consumer** — only `ChecklistViewModelTests.swift:7-8` constructs it.

**The edit screen** (`CheckStitch/ChecklistDetailView.swift:21-89`) is a `Form`
with a buffered `@State draftName` committed on Done/exit (`:66-70, 91-103`) and
per-keystroke item bindings (`:105-112`); its only alert is the rename-conflict
alert (`:78-84`). `Picker` with `.tag` rows already exists twice in settings
(`SettingsView.swift:17`, `BackgroundSettingsView.swift:23`), and `.alert` is
the established error-surface idiom.

**Merge** unions tombstones and lets the newest checklist winner overwrite only
`name` / `revision` / `modifiedAt` (`CheckStitch/ChecklistMerge.swift:73-82`).
The watch target has its own `WatchChecklistStore` over the same core model.

## Desired End State

The edit-checklist screen gains a destination-list selector. The choice is
persisted with the checklist and syncs/merges like any other field. When the
checklist is run:

- **Happy path:** reminders are created in the chosen list; if no choice was
  made (`nil`), reminders go to the system default list exactly as today.
- **Missing-list path:** if the stored destination no longer exists, the app
  shows an error and creates **zero** reminders.
- **Permission-denied path:** surfaced as an error instead of the current
  silent success (the run must not falsely flash success).

Correctness checks:
- An existing stored checklist (no destination field) still decodes, loads, and
  runs to the system default.
- A playlist with a valid destination creates in that list.
- Deleting the list in Reminders, then running the checklist, produces an error
  and no reminders (verify in Reminders.app).
- Round-trip: destination survives save/load and a device merge.

## Patterns to Follow

- **Model field + codec:** add the field to `Checklist` as a `??`-defaulted
  optional in `init(from:)` (`Checklist.swift:71-75`), encode unconditionally,
  and keep `currentVersion = 2` (no migration needed — decision 4).
- **Store mutation + revision:** model the setter on `ChecklistStore.rename`
  (`ChecklistStore.swift:120-130`) — an outcome enum for not-found, bump
  `revision`/`modifiedAt`, then `scheduleSave()`; `flushPendingSave()` already
  covers exit/scene-phase (`ChecklistDetailView.swift:75`, `MyApp.swift:51-56`).
- **Merge:** extend the checklist-winner overwrite set
  (`ChecklistMerge.swift:73-82`) to include the destination, mirroring `name`.
- **UI control:** copy the two existing settings `Picker`s with `.tag` rows and
  a staged binding (`SettingsView.swift:17`, `ContentView.swift:361-369`); put it
  in the detail `Form` as a new `Section`.
- **Error surface:** copy the rename-conflict `.alert` idiom
  (`ChecklistDetailView.swift:78-84`); the run error belongs on the list screen
  where the run button lives.
- **Tests:** add XCTest codec cases in `ChecklistCodecTests.swift` (v2 payload
  without the field → `nil`; round-trip) and Swift Testing cases via the
  `SpyReminderCreator` seam (`TestFixtures.swift:28-49`). Keep real EventKit to
  construction canaries (`EventKitReminderCreatorTests.swift:13-16`) because
  `EKReminder` holds a weak store ref that SIGTRAPs on dealloc
  (`TestFixtures.swift:22-27`).

**Patterns NOT to follow:**
- `ChecklistReminders.create`'s silent `Void` + log-only errors
  (`ChecklistReminders.swift:10-28`) — this is the bug being fixed.
- Per-item `save(commit: true)` with no pre-validation as an "atomic" story
  (`ChecklistReminders.swift:21-22`) — existence must be validated first.
- SingleThread's title-as-identity precedent (`ReminderStore.swift:494-505`) —
  not stable across renames.
- Introducing a `Menu`/`.pickerStyle(.menu)` surface — the app has none.

## Design Decisions

1. **Identity: persist `EKCalendar.calendarIdentifier` as
   `destinationListIdentifier: String?`.** A stable opaque Identifier (unlike
   `title`) that survives list renames and app restarts; `nil` means "system
   default list", preserving today's behaviour for legacy payloads. Deletion is
   detected by absence from `calendars(for: .reminder)`. A rename keeps the
   checklist valid. *(Implementation should add a small construction/canary test
   confirming the identifier is populated and stable on this toolchain — see
   Open Risks.)*

2. **Pre-validate before creating anything.** Before the loop, enumerate
   `eventStore.calendars(for: .reminder)` and resolve the destination: if
   `destinationListIdentifier == nil`, use
   `defaultCalendarForNewReminders()`; otherwise find the calendar whose
   `calendarIdentifier` matches. If resolution fails (list gone, or no default
   list), return a failure outcome and create **zero** reminders. This satisfies
   the ticket's all-or-nothing existence guarantee without introducing deletion
   or rollback.

3. **Rework the production path in place.** Change
   `ChecklistReminders.create(from:)` to accept/read the destination and return
   an outcome (`.created` / `.destinationMissing` / `.permissionDenied` /
   `.failed`), assigning each `EKReminder.calendar` to the resolved list (default
   when `nil`). `ContentView.createReminders(for:)` switches on the outcome: on
   `.created` keep the existing success state; otherwise present an `.alert` and
   do not mark success. The unused core `ChecklistCreator` path is left as-is.

4. **Destination merges like `name`; no version bump.** The checklist-level
   merge winner overwrites the destination along with `name`/`revision`/
   `modifiedAt` (`ChecklistMerge.swift:73-82`), so the most recent editor
   controls the list. `currentVersion` stays `2`: the field decodes via `?? nil`
   for legacy payloads and encodes unconditionally, so no migration strut is
   needed and older peers keep syncing. (Trade-off accepted: an older build
   re-encoding a v2 payload will drop the field; this is the existing
   forward-compat behaviour and is why we chose not to freeze peers with a v3
   read-only guard.)

5. **Selector prompts on the edit screen.** `ChecklistDetailView` gains a
   "Destination list" `Section` with a `Picker` built from
   `calendars(for: .reminder)` (title as label, `calendarIdentifier` as tag),
   plus a first "Default (Inbox)" row tagged `nil`. On appear it requests full
   access and enumerates; if access is denied or enumeration is empty, it shows
   the "Default (Inbox)" row only with an explanatory note. Committing the
   selection goes through a new `ChecklistStore.setDestination(...)` that
   follows the `rename` outcome pattern and schedules the save.

## What We're NOT Doing

- No reminder deletion or rollback on partial failure — the app never deletes
  reminders; only *existence* is validated up front.
- No migration of the `"checklists.v1"` storage key and no `currentVersion`
  bump.
- No watch selector UI; the watch model decodes and round-trips the new field
  only.
- No adoption/re-wiring of the core `ChecklistCreator` / `ChecklistViewModel` /
  `AppEnvironment` path.
- No list creation, renaming, or reordering from CheckStitch — selection only.
- No per-item failure state or partial-created count in the UI.

## Open Risks

- **`EKCalendar.calendarIdentifier` stability** on this toolchain (Xcode 26.6 /
  iOS 27.0) is assumed from the SDK, not confirmed in-repo. Mitigate with a
  canary/construction test plus a live device check; the design only depends on
  the identifier being non-empty and round-trippable, with a title fallback
  possible if it proves unreliable.
- **Permission requested from the edit screen** is a new prompt location; if
  users deny, the selector degrades to default-only and a run still surfaces a
  permission error (decision 3), so no silent success remains.
- **Merge divergence**: winner-takes-all can move a checklist to a list that
  doesn't exist on another device — that device's next run will (correctly) error
  until it picks a list. Acceptable per decision 4, but worth watching in
  review.
- **`defaultCalendarForNewReminders()` can be `nil`**; treated as
  `.destinationMissing` and surfaced, not silently skipped.