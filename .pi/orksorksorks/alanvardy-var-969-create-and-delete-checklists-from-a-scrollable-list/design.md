# Design Discussion

## Current State

CheckStitch is a single 166-line screen. `MyApp.swift:4-9` declares one
`WindowGroup { ContentView() }`. `ContentView.swift:6-16` holds **all** app
state as `@State`: `checklistName`, `items`, `isShowingEditChecklist`,
`isCreatingChecklist`, `isChecklistCreated`. There is no checklist-level type —
only `ChecklistItem` (`ContentView.swift:106-117`, stable `UUID` id + mutable
title) — and nothing persists: no file I/O, no App Group usage anywhere in
`CheckStitch/`.

The screen is an `HStack` of two buttons (`ContentView.swift:17-26`):
`createChecklistButton` (`ContentView.swift:28-60`) drives an implicit checklist
through a `Task` that sets a spinner, enforces a 1s minimum sleep, calls
`createChecklistReminders()`, then flashes a green checkmark for 1s; and
`editChecklistButton` (`ContentView.swift:62-79`) opens the edit sheet.
`createChecklistReminders()` (`ContentView.swift:81-104`) requests full Reminders
access, builds one `EKReminder` per non-blank item, assigns
`defaultCalendarForNewReminders()` and saves with `commit: true`, logging
failures through `Self.logger` (`ContentView.swift:5`).

`EditChecklistView` (`ContentView.swift:119-166`) is a `.sheet` with
`@Binding name` / `@Binding items` writing straight back to `ContentView`'s
`@State`, a `ForEach($items)` with `.onDelete`, an "Add Item" button, and
**both** a "Remove Checklist" button and a toolbar "Done" that simply call
`dismiss()` (`ContentView.swift:133-143`) — the two are behaviorally identical,
which is the no-op superseded by this ticket (VAR-967 / commit ce0b479).

The App Group is registered but unused: `CheckStitch/AppGroup.entitlements:1-10`
declares `group.app.alanvardy.CheckStitch`, wired as `CODE_SIGN_ENTITLEMENTS`.
The only cross-app persistence precedent on this machine is SingleThread's
`AppGroup.defaults = UserDefaults(suiteName:) ?? .standard`
(`AppGroup.swift:8-19`) plus store structs that take
`defaults: UserDefaults = AppGroup.defaults, key: String = <key>`
(`CompletionCounterStore.swift:12-18`, `ExcludedListStore.swift:7`).

## Desired End State

The main screen is a scrollable list of checklists; a "Create checklist" action
adds an empty checklist and pushes it open; tapping a row pushes that checklist
open; the detail screen renames, adds, removes and edits items exactly as today;
"Remove Checklist" deletes the checklist locally and pops the screen. Checklists
survive relaunch.

Correctness is verifiable by:
1. Create two checklists with distinct names and items, force-quit, relaunch —
   both reappear with names and items intact.
2. Create reminders from one checklist, hit its green checkmark, then Remove
   Checklist — the checklist disappears from the list, and the reminders remain
   untouched in Reminders.
3. Edit a checklist, relaunch, edits persist.
4. `./scripts/test.sh` prints `gate: ok` (build + shellcheck).

State lives in the App Group suite so the planned watch app (VAR-963) can read
the same payload. Removal never touches Reminders.

## Patterns to Follow

- **App Group accessor** — mirror SingleThread `AppGroup.swift:8-19`:
  `suiteName = "group.app.alanvardy.CheckStitch"`, `defaults` computed as
  `UserDefaults(suiteName: suiteName) ?? .standard`. The `.standard` fallback is
  deliberate: unregistered simulators/previews must not crash (SPIKE
  `WatchAppGroupHarness.md` records group-vs-standard divergence).
- **Store struct with injectable defaults/key** — `defaults: UserDefaults =
  AppGroup.defaults, key: String = <defaultsKey>` (SingleThread
  `CompletionCounterStore.swift:12-18`). Injecting `UserDefaults(suiteName:)`
  per test instance is the testability seam this repo should copy even though
  there is no test target yet.
- **UserDefaults API only** — `set(_:forKey:)` writes, `data(forKey:)` /
  `removeObject(forKey:)` reads and deletes (`CompletionCounterStore.swift:29-33`,
  watch tests `WatchSyncPipelineTests.swift:395`). No `NSFileManager` container
  APIs: they exist in the SDK (`NSFileManager.h:452-454`) but no Swift here uses
  them.
- **`EKReminder` event-store lifetime** — the store must outlive the reminders
  (SingleThread `WatchReminderView.swift:378-380`); keep `createChecklistReminders`
  constructing one `EKEventStore` per call as it does today
  (`ContentView.swift:83`).
- **Usage-description keys** — `INFOPLIST_KEY_NSRemindersUsageDescription` and
  `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` are already set in both
  configurations (`project.pbxproj:261-263, 303-305`); do not regress them.
- **New files under `CheckStitch/` need no `project.pbxproj` edit**
  (`PBXFileSystemSynchronizedRootGroup`); `scripts/*.sh` stay
  `#!/bin/bash` + `set -euo pipefail`, mode `100755`.

Patterns **not** to follow:
- The no-op Remove button (`ContentView.swift:133-143`, ce0b479) — Remove must
  actually delete.
- `@State` on the view as the sole source of truth (`ContentView.swift:6-16`) —
  it cannot survive relaunch and cannot be shared with the watch app.
- Hardcoded `name=` simulator destinations (repo AGENTS.md / `Makefile:4-6`).
- There is **no** reminder-deletion pattern to copy in either repo — do not
  invent one.

## Design Decisions

1. **Persistence mechanism (Q1A)**: `Codable` JSON encoded into
   `UserDefaults(suiteName: "group.app.alanvardy.CheckStitch")` via an
   `AppGroup.defaults` accessor. It is App Group container storage, matches the
   proven SingleThread/SPIKE pattern, is watch-readable, and the payload
   (names + strings) is tiny. A file in the container URL was rejected: the SDK
   supports it but no Swift here uses it, so we would invent atomic-write and
   error-handling conventions from nothing.

2. **Payload shape (Q2B)**: one key holds an envelope
   `{ "version": 1, "checklists": [Checklist] }`, not a bare array. The watch
   wire format is unconfirmed (research Open Areas), so the version field is the
   cheap hedge that lets VAR-963 evolve decoding without a silent mis-read.
   Unknown-version payloads are treated as empty (log, do not crash).

3. **Model**: a new `Checklist` struct (`id: UUID`, `var name: String`,
   `var items: [ChecklistItem]`), `Identifiable`, `Codable`, `Hashable`; the
   existing `ChecklistItem` (`ContentView.swift:106-117`) moves into the shared
   model file unchanged (keep the stable `UUID` id). The store owns a
   `[Checklist]`; the envelope is a separate `Codable` type.

4. **Delete semantics (Q3A)**: Remove Checklist deletes only the local record
   and pops the detail screen. Removing a single item deletes only the local
   item. Reminders already saved to Reminders are never queried or deleted —
   consistent with both repos, where nothing removes reminders (research Q2).
   This confirms the open product question in `task.md`.

5. **Navigation (Q4B)**: replace the sheet with a `NavigationStack` on
   `ContentView`; a `List` of checklists with `NavigationLink(value:)` pushes a
   new `ChecklistDetailView` derived from `EditChecklistView`. Create appends an
   empty checklist and pushes it (via a `NavigationPath` / `[UUID]` path so the
   push is programmatic). Remove calls the store then pops via path removal or
   `dismiss()`. The detail view mutates the store by checklist id rather than a
   `@Binding` into a view's `@State`.

6. **Create feedback (Q5A)**: the VAR-966 spinner/minimum-1s/green-checkmark
   flow (`ContentView.swift:28-60`) stays, but per-checklist transient state
   keyed by checklist id lives in the list view (or a small view model); it is
   not persisted. Tapping Create again re-creates reminders — pre-existing
   behavior, tracked as a risk, not fixed here.

7. **Store type**: an `@Observable` (iOS 17+) store class wrapping the
   `AppGroup.defaults` read/write/save, injected into the view hierarchy. It is
   the first persistence subsystem in this dependency-free project, so keep it
   one file with no third-party code.

8. **Proposed file layout** (all under `CheckStitch/`, no pbxproj edit):
   `AppGroup.swift` (accessor), `Checklist.swift` (model + envelope),
   `ChecklistStore.swift` (load/save/mutations), `ContentView.swift` (list
   screen + create flow), `ChecklistDetailView.swift` (renamed/extracted edit
   screen). `MyApp.swift` injects the store.

## What We're NOT Doing

- Deleting or mutating reminders in Reminders (Option 3B explicitly rejected) —
  no `EKReminder` lookup, no `remove`, no stored reminder identifiers.
- Any watch-app (VAR-963) code; this ticket only guarantees the shared payload
  is available and versioned.
- Migration/back-compat for previously persisted data — none exists today, and
  first launch yields an empty list.
- Test target, UI tests, or CI — the gate remains `make build` + shellcheck per
  `scripts/test.sh:1-15` and repo AGENTS.md.
- Cross-device sync conflict resolution; last write wins within the shared
  suite.
- Changing `createChecklistReminders()`'s EventKit behavior (blank-skipping,
  inbox calendar, `commit: true`, logging) beyond adapting it to take a
  `Checklist` argument.

## Open Risks

- **Watch wire format unconfirmed** (research Open Areas) — the version field
  covers decoding ambiguity, but VAR-963 may still want a different key name or
  structure. Keep the envelope minimal and document the key.
- **`.standard` fallback masks sharing** — on an unregistered simulator,
  persistence "works" but is not shared. Verify App Group behaviour against the
  real device path (`scripts/run-devices.sh`) as well as the simulator.
- **Duplicate reminders** — because the flag is transient (decision 6), a user
  can press Create twice and duplicate rows in Reminders; accepted scope.
- **Navigation path after delete** — removing the checklist currently being
  viewed must pop cleanly without a stale id in the path; test this explicitly.
- **`EKEventStore` lifetime** — the store is local to `createChecklistReminders`
  today; keep it alive until all saves complete (SingleThread
  `WatchReminderView.swift:378-380`).
- **Codable drift** — a future `ChecklistItem` field must decode leniently for
  old payloads; if the schema changes, bump `version` rather than silently
  dropping data.
- **First launch** — empty list must render an encouraging empty state, not a
  blank screen, since the old app always showed a default "checklist".
