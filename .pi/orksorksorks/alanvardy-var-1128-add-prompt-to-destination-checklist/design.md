# Design Discussion

## Current State

- A checklist's destination is `Checklist.destinationListIdentifier: String?`
  (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:212`): `nil` = system
  default list, otherwise an `EKCalendar.calendarIdentifier`. Absent keys decode
  tolerantly to `nil` (`:268`), encode unconditionally (`:314`), and ride the
  checklist's coarse `revision`/`modifiedAt` clock (`:168-170,209-215`), so no
  version bump or migration path exists today (`ChecklistCodec.currentVersion = 5`,
  `classify` at `:595-618`).
- One run funnel: `ChecklistReminders.create(from:)` → shared
  `create(from:targeting:gate:multipleOverride:)`
  (`CheckStitchCore/.../ChecklistReminders.swift:8-20,24-84`), ordered
  gate → permission → destination resolve → per-item create
  (`:39-54`). Destination resolves via
  `ReminderListsSnapshot.resolve(checklist.destinationListIdentifier)`
  (`:51`; `ReminderDestinationTargeting.swift:28-40`), which maps `nil` to the
  system default and returns `nil` (→ `.destinationMissing`) for an unknown id.
- Outcomes are `ReminderRunOutcome` (`.created`, `.destinationMissing`,
  `.permissionDenied`, `.purchaseRequired`, `.partiallyCreated`, `.failed` —
  `ReminderDestinationTargeting.swift:69-104`).
- Entry points: app UI (`ContentView.swift:727-751` +
  `ChecklistRunViewModel.swift:38-68`), `RunChecklistIntent` (the only run
  intent, `openAppWhenRun = false`, `CheckStitchCore/.../RunChecklistIntent.swift:22-110`),
  the widget (`Button(intent:)`, `SingleChecklistWidget.swift:126`,
  `MultiChecklistWidget.swift:60`), and the watch (request/reply over
  WatchConnectivity, `ChecklistSyncCoordinator.swift:86-136`,
  `ChecklistSync.swift:303-337`).
- Destination config lives in the detail picker: "Default (Inbox)" + list rows
  bound through `store.setDestination` (`ChecklistDetailView.swift:54-68,361-370`),
  with `destinationIsStale` warning for unknown ids (`:287-293`).
- `checkstitch://` is already a registered URL scheme
  (`CheckStitch/Info.plist:20-28`) but the sole `onOpenURL`
  (`ContentView.swift:167-170`) feeds *every* URL into
  `SharedImportInbox.receive` with no scheme filtering.
- Sync merges whole checklists by LWW (`revision`, then `modifiedAt`, then
  device id) and copies destination as part of the winner
  (`ChecklistMerge.swift:136-152,283-289`).

## Desired End State

A checklist's destination is one of three mutually exclusive states: the system
default list, a specific reminder list, or **prompt** — ask at the moment of
running. A prompt checklist:

- shows "Ask me each time" in the detail picker;
- presents an in-app sheet listing destination options when the user taps Run,
  and runs once a list is chosen (the choice is not persisted);
- when run from Siri or the Shortcuts app, asks for the list through the
  system's own parameter prompt (works with `openAppWhenRun = false`);
- when run from a widget, opens the app to the prompt sheet for that checklist;
- when run from the watch, replies "Choose a list on iPhone" instead of
  creating reminders.

Verification: `make test-unit` for the codec/store/merge/run/intent suites,
`bash scripts/l10n-check.sh` for the new strings, then the full
`./scripts/test.sh` gate; headless intent prompting is compiler-verified by
`RunChecklistIntentTests`, and the widget/watch copy by their suites.

## Patterns to Follow

- **Additive, tolerant codec discipline**: follow the existing field handling —
  `decodeIfPresent` for absence tolerance (`Checklist.swift:268`), unconditional
  encode (`:314`), and the versioned `classify`/migration machinery
  (`ChecklistCodec.swift:595-618`) when changing shape.
- **One run funnel**: every entry point must go through
  `ChecklistReminders.create(from:targeting:gate:multipleOverride:)`
  (`ChecklistReminders.swift:24-84`); add the prompt behaviour there, not at each
  call site.
- **Seam injection for tests**: the intent and run VM inject `targeting`
  (`RunChecklistIntent.swift:61`, `ChecklistRunViewModel.swift:15`); keep the new
  destination resolution injectable the same way.
- **`AppEntity` + `defaultQuery` precedent** for the intent parameter:
  `ChecklistEntity`/`ChecklistEntityQuery` (`ChecklistEntity.swift:6-53`),
  including the injected-store pattern (`:22-28`) and `EntityStringQuery`.
- **Enum + `Picker` precedent**: `ReminderListsSnapshot.selectableOptions` /
  `pickerSelection(for:)` (`ReminderDestinationTargeting.swift:45-58`) are the
  option model the detail picker and new sheet should share.
- **Localization discipline**: four catalogs, six languages, a
  `LocalizationFixtures.requiredKeys` entry per new key, checked by both
  `scripts/l10n-check.sh` and `LocalizationTests`.
- ⚠️ **Do NOT follow**: the unfiltered `onOpenURL` at `ContentView.swift:167-170`
  (it swallows any URL as a file import); the new deep-link handler must filter
  by scheme/host before calling `SharedImportInbox.receive`.
- ⚠️ **Do NOT follow**: the hardcoded alert title at `ContentView.swift:179`
  (research's known bug); new strings go through the catalogs.

## Design Decisions

1. **Represent the prompt state as a new enum `ChecklistDestination`**
   (`.systemDefault`, `.list(String)`, `.prompt`) replacing the bare
   `String?` — a third state that must never collapse into "default", so a single
   typed value is the only safe representation (`Checklist.swift:212`).
2. **Encode as a single-value custom `Codable` under a new `destination` key**
   (`"systemDefault"`/`"prompt"` strings, `{"list":"<identifier>"}` for a
   concrete list) — one self-describing value, no two-field coherence drift, and
   no overloaded `destinationListIdentifier` namespace.
3. **Bump `ChecklistCodec.currentVersion` 5 → 6 with a v5→v6 migration**, and
   extend `classify` to `.migratable(from: 1-5)` plus the remote-migration branch
   (`ChecklistSyncService.swift:119-145`); v5 maps `nil → .systemDefault`,
   string → `.list(id)`. The version gate is what stops an old build applying new
   bytes and misreading a prompt checklist as Inbox (`canAcceptRemoteChanges`,
   `ChecklistStore.swift:31,38-95`).
4. **Replace `destinationListIdentifier` with `destination: ChecklistDestination`
   at every call site** — `ChecklistReminders.swift:51`, `ChecklistMerge.swift:150`,
   `ChecklistStore.setDestination` (`:346-355`) and `duplicate`/`freshCopy`
   (`:262-281`), `ChecklistDetailView.destinationBinding` (`:361-370`) and
   `destinationIsStale` (`:287-293`), export. A computed `String?` adapter would
   collapse `.prompt` and `.systemDefault` to the same `nil` and silently
   reintroduce the bug.
5. **Thread the prompt through the funnel with an optional override**:
   `ChecklistReminders.create` gains `destination: ChecklistDestination?`; when
   `checklist.destination == .prompt` and the override is absent it returns a new
   `.destinationRequired` outcome, otherwise it resolves `.list`/`.systemDefault`
   exactly as today (`ChecklistReminders.swift:50-54`). The app sheet and the
   intent both pass a resolved `.list(id)`.
6. **The app UI presents a destination sheet** when Run is tapped on a prompt
   checklist: rows from `ReminderListsSnapshot.selectableOptions` plus "Default
   (Inbox)", then Run / Cancel. Reuses the existing option model
   (`ReminderDestinationTargeting.swift:45-58`) instead of a second picker.
7. **The choice is one-shot** — used for that run only; the checklist stays
   `.prompt`. Nothing is written back to the store, so the choice never syncs
   (`ChecklistStore.swift:799-815`).
8. **The detail picker gains a third row, "Ask me each time"** (`ChecklistDetailView.swift:54-68`),
   writing the whole enum; `destinationIsStale` (`:287-293`) applies only to
   `.list` ids absent from the snapshot.
9. **`RunChecklistIntent` gains an optional `ReminderListEntity` `destination`
   parameter** (new `AppEntity` + query in `CheckStitchCore`, modelled on
   `ChecklistEntity.swift:6-53`, enumerating EventKit lists plus a synthetic
   "Default (Inbox)"). `perform()` calls `await $destination.requestValue(...)`
   only when the checklist is `.prompt`, after the access status pre-check
   (`RunChecklistIntent.swift:77-85`) so the picker is permission-gated; the query
   degrades to the synthetic default when unauthorized. `requestValue` prompts in
   Siri and Shortcuts with `openAppWhenRun = false` (SDK-confirmed, iOS 16+).
10. **Where the intent cannot prompt it returns `.destinationRequired`** — the
    widget-button context runs headless with no presenter, so it must guard the
    missing value itself.
11. **Widget hand-off for prompt checklists**: set `widgetURL` to a
    `checkstitch://run?checklist=<id>` URL and withhold the interactive
    `Button(intent:)` (`SingleChecklistWidget.swift:126,139`,
    `MultiChecklistWidget.swift:60,78`). `ContentView`'s `onOpenURL`
    (`:167-170`) is extended to filter `checkstitch://` run URLs and route them
    to the prompt sheet before `SharedImportInbox.receive`. No new scheme needed
    (`CheckStitch/Info.plist:20-28`).
12. **Watch runs return `.destinationRequired`** through the existing
    request/reply (`ChecklistSyncCoordinator.swift:120-136`; wire kinds at
    `ChecklistSync.swift:33-116`), surfaced as "Choose a list on iPhone". No
    destination data crosses the watch boundary (`ChecklistSync.swift:303-337`).
13. **One vocabulary for the state**: `ReminderRunOutcome.destinationRequired`,
    the intent's `RunChecklistDialogue` case, and the watch's `RunResultKind`
    all use the name `destinationRequired`; it is distinct from
    `.destinationMissing` (a stored id that no longer exists).
14. **The sheet requests Reminders access when it opens** and, on denial,
    dismisses and routes through the existing permission-denied run error
    (`ChecklistReminders.swift:45-48`) rather than showing an empty list.
15. **All new strings are localized** across the four catalogs (App: sheet title,
    "Ask me each time"; Core: intent dialogue; Watch: "Choose a list on iPhone")
    with six languages each and `LocalizationFixtures.requiredKeys` entries.
16. **Merge/sync keep whole-checklist LWW** — the enum is copied with the winner
    exactly as the string is today (`ChecklistMerge.swift:150`); there is no new
    per-field clock, and concurrent prompt-vs-list edits resolve by the winner.

## What We're NOT Doing

- Not persisting the run-time choice, and not "remembering the last choice" —
  the checklist stays `.prompt` (decision 7).
- Not adding a per-field clock or field-level merge for destination (decision 16).
- Not introducing a `String?` back-compat accessor or a sentinel string (decisions 3–4).
- Not registering a new URL scheme — `checkstitch` already exists (decision 11).
- Not adding a destination parameter to `ChecklistConfigurationIntent` /
  `MultiChecklistConfigurationIntent` — those are widget config pickers, not run
  intents.
- Not making the watch prompt or carry destination data; the phone owns EventKit
  (decision 12).
- Not changing the gate → permission ordering inside the existing funnel, and not
  adding any new purchase/run-count behaviour.
- Not creating child tickets — all work happens on the main ticket
  (`task.md`).

## Open Risks

- **`requestValue` in a widget context is inert**: the design routes widget runs
  through the deep-link instead of relying on it, but any future entry point that
  calls `requestValue` headlessly must guard the unset case.
- **`EntityQuery` enumeration needs Reminders permission**: if the access
  pre-check is `.notDetermined`, the picker may show only the synthetic default.
  The intent already short-circuits with `.notDetermined`/`.denied` dialogs, but
  ordering should be verified by a test.
- **`onOpenURL` is currently unfiltered** (`ContentView.swift:167-170`); the run
  handler must filter strictly, or a malformed `checkstitch://` payload could
  still reach `SharedImportInbox`.
- **v5 bytes from a v5 device during rollout**: the version gate rejects them
  rather than misreading — intended, but it means cross-version sync is one-way
  until both devices update.
- **Watch `.destinationRequired` copy** and the exact intent dialogue strings were
  not transcribed in research; they must be added in all six languages or
  `l10n-check.sh` fails.
- **`Checklist` has no explicit `Equatable` guarantee on the new enum**; merge's
  `merged != envelope` idempotence guard (`ChecklistStore.swift:740`) depends on
  enum equality — confirm `ChecklistDestination: Equatable` (and `Hashable` if
  needed for picker tags).