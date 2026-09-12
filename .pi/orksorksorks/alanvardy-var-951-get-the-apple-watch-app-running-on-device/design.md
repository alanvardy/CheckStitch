# Design Discussion

## Current State

CheckStitch is a single-target iOS/macOS app. One `PBXNativeTarget "CheckStitch"`
(`CheckStitch.xcodeproj/project.pbxproj:48-67`), sources pulled implicitly from
the `PBXFileSystemSynchronizedRootGroup` over `CheckStitch/` — the
`PBXSourcesBuildPhase` is empty, so new files need no pbxproj edit
(`project.pbxproj:13-19, 55-61, 109-115`). Per-target settings are
`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (:282),
`TARGETED_DEVICE_FAMILY = "1,2"` (:288), `SWIFT_VERSION = 6.0`,
`DEVELOPMENT_TEAM = 6NWX2DHB9Q` (:257), `GENERATE_INFOPLIST_FILE = YES` (:261),
App Group `group.app.alanvardy.CheckStitch` (`CheckStitch/AppGroup.entitlements:5-10`).
The project-level file already carries `WATCHOS_DEPLOYMENT_TARGET = 27.0` (:183).

The app is a two-file SwiftUI program: `MyApp.swift:3-7` (`@main` →
`WindowGroup { ContentView() }`) and `ContentView.swift`. `ContentView` holds
**one** checklist in local state — `checklistName`/`items: [ChecklistItem]`
(`ContentView.swift:26-31`) — with an edit sheet driven by `EditChecklistView`
(:115-162). Tapping Create runs `createChecklistReminders()`
(`ContentView.swift:86-105`): `EKEventStore()` (:87) →
`requestFullAccessToReminders()` (:89) → for each non-blank item an
`EKReminder(eventStore:)` (:95-96) with `calendar = defaultCalendarForNewReminders()`
(:97) → `save(reminder, commit: true)` (:98). **The checklist itself is never
persisted and never enumerated** — there is exactly one, it lives only in
`@State`, and the reminders it produced are indistinguishable from any other
Inbox reminder.

There is no watch target, no watch sources, no `CheckStitch` scheme for watch,
and no watch build/run tooling. `Makefile:4-9` defines the iOS simulator
destination precedence (`SIM=` > `.simulator_id` > `iPhone 17`) and
`build`/`run`/`clean` (:13-24) for the single scheme. `scripts/test.sh` is the
only gate — `make build` plus `shellcheck scripts/*.sh` (falling back to `bash -n`);
there is no test target. `scripts/run-devices.sh` installs/launches on physical
**iPhone/iPad** only (`devicectl device install app` / `device process launch`);
nothing in either repo installs a **watch** app anywhere, and the real device
`Alan's Apple Watch` (`00008301-209B793C010BC02E`, Apple Watch Ultra, paired,
available) is reachable via `devicectl` today.

The reference implementation is `/Users/vardy/dev/SingleThread`. Its
`SingleThreadWatch` target demonstrates the recipe we are copying:
`SDKROOT = watchos`, `SUPPORTED_PLATFORMS = "watchos watchsimulator"`,
`TARGETED_DEVICE_FAMILY = 4`, `SKIP_INSTALL = YES`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, a `.watchkitapp` bundle-id suffix,
`GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` /
`INFOPLIST_KEY_WKWatchOnly = NO` / `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription`
(`SingleThread.xcodeproj/project.pbxproj:940-1016`), and source inclusion via a
`PBXFileSystemSynchronizedRootGroup` (:126-130, :328-330). The iOS target embeds
it through an "Embed Watch Content" copy phase (`pbxproj:69-75`) plus a
`PBXTargetDependency` (:592-597). Crucially, **watchOS EventKit is read-only** —
SingleThread compiles `save`/`remove`/`makeReminder` out behind `#if !os(watchOS)`
(`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:34-37`) and
relays mutations to the phone over WatchConnectivity. CheckStitch's watch must do
the same, because the reminders are created by `EKEventStore.save(commit: true)`,
which does not exist on watchOS.

## Desired End State

The iOS app remains the **authoring** surface: you build a checklist, and
tapping Create both **persists the checklist definition** (name + items) and
**runs it** — writing one reminder per item into the Inbox exactly as today.
No new iOS UI.

A new **companion watch app** (`CheckStitchWatch`, `WKWatchOnly = NO`, embedded
in `CheckStitch.app`) becomes the **runner**. On launch it fetches the saved
checklist set from the phone, shows a list of checklists, and picking one opens
a read-only item list with a **Run** button. Running sends a
`transferUserInfo` message to the phone, which creates one `EKReminder` per item
in `defaultCalendarForNewReminders()` and acknowledges; the watch shows a
"Queued" state until the phone has accepted it.

Correct means, verifiable on the real watch:

1. `make watch-build` succeeds for `generic/platform=watchOS`, and the iOS
   build still succeeds with the watch app embedded.
2. `scripts/run-watch.sh` installs and launches `CheckStitchWatch` on
   `Alan's Apple Watch`.
3. Creating a checklist on the iPhone makes it appear in the watch's list.
4. Tapping Run on the watch produces one Reminder per checklist item in the
   Inbox, visible on both the phone and the watch.

## Patterns to Follow

- **Watch target recipe** — copy SingleThread's watch build settings verbatim
  (`pbxproj:940-1016`): `SDKROOT = watchos`,
  `SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `TARGETED_DEVICE_FAMILY = 4`,
  `SKIP_INSTALL = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
  `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitch.watchkitapp`,
  `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, `CODE_SIGN_STYLE = Automatic`,
  `GENERATE_INFOPLIST_FILE = YES`.
- **Companion embedding** — "Embed Watch Content" copy phase
  (`dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`, iOS platform filter) plus a
  `PBXTargetDependency` on the iOS target (`pbxproj:69-75`, :592-597), and
  `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = app.alanvardy.CheckStitch`,
  `INFOPLIST_KEY_WKWatchOnly = NO` (:950-952).
- **Source inclusion** — add `CheckStitchWatch/` as a
  `PBXFileSystemSynchronizedRootGroup` referenced by the watch target's
  `fileSystemSynchronizedGroups`; never hand-list watch files in a build phase.
- **Signing split** — the watch configs get **no** `CODE_SIGN_ENTITLEMENTS`
  (team-based automatic signing, as in SingleThread); the existing
  `[sdk=iphoneos*]`/`[sdk=iphonesimulator*]` entitlements on the iOS target stay
  as they are (`CheckStitch project.pbxproj:253-255`). On a machine without the
  profile, build with `-allowProvisioningUpdates`.
- **Reminder creation pattern** — reuse `EKReminder(eventStore:)` →
  `calendar = eventStore.defaultCalendarForNewReminders()` →
  `try eventStore.save(reminder, commit: true)`, skipping blank titles
  (`ContentView.swift:94-98`). This is the documented CheckStitch/SingleThread
  pattern (SingleThread `AGENTS.md:45`). It runs **on the phone**, never on the watch.
- **@MainActor + SwiftUI shell** — watch entry `@main struct …App` building a
  `WindowGroup`, state held in `@MainActor @Observable` objects, views switching
  on state; mirrors `SingleThreadWatch/SingleThreadWatchApp.swift:3-15` and
  `WatchReminderView.swift:47-63`. Permission UI: `.notDetermined` → progress,
  granted → content, otherwise a "Settings" message.
- **Scripts** — `#!/bin/bash` with `set -euo pipefail`, mode `100755`, resolved
  destinations (`…,id=<UDID>`) rather than bare `name=`, and UDID resolution via
  `xcrun simctl list devices available` / `xcrun devicectl list devices -j` +
  python filter (`scripts/run-simulator.sh`, `scripts/run-devices.sh`).
- **Gate** — extend `scripts/test.sh`; it stays build + shellcheck, never a test
  target.

Patterns found in the research that must **not** be copied:

- **Compiling the shared EventKit code for both platforms** — SingleThread puts
  its store in a package with `#if os(watchOS)` branches throughout. CheckStitch
  has no such shared store and should not grow one: keep EventKit writes on iOS
  only and have the watch send messages.
- **`InMemoryEventStore` / UI-test seeding** — SingleThread's test seams exist
  only because it has test targets; CheckStitch has none and this ticket does not
  add any (SingleThread watch suites, `conventions.md` test inventory).
- **A bare `name=` watch destination in a script** — it selects a shared
  simulator and wedges parallel agents (`conventions.md`, Makefile comment).

## Design Decisions

1. **Companion, not standalone**: `WKWatchOnly = NO`, embedded in
   `CheckStitch.app`, `WKCompanionAppBundleIdentifier = app.alanvardy.CheckStitch`
   — mirrors the only working precedent and is what enables WatchConnectivity.
2. **Checklists persist on the iPhone** (source of truth) as a Codable
   `Checklist` (id, name, items) written to the phone's app container; the watch
   holds a **cache** in its own container. App Group containers are per-device
   and do **not** sync iPhone↔Watch, so persistence alone can never deliver
   checklists to the watch.
3. **Transport is WatchConnectivity.** `updateApplicationContext` carries the
   checklist set (latest-state semantics, survives the counterpart being
   unreachable); `transferUserInfo` carries run triggers (queued commands).
   The watch requests the current set on launch.
4. **Running is creation.** A trigger is a `{checklistID}` message; the phone
   re-reads the persisted checklist and writes one `EKReminder` per non-blank
   item into `defaultCalendarForNewReminders()`.
5. **iOS Create stays a run action.** Creating a checklist persists it *and*
   writes its reminders immediately — the existing behaviour is preserved.
6. **No dedicated reminders list** — items go to the Inbox
   (`defaultCalendarForNewReminders()`) "for now"; a named CheckStitch list is a
   later ticket.
7. **`CheckStitchCore` Swift package** owns `Checklist`, its Codable form, and
   the WatchConnectivity message keys; both targets import it. A shared type now
   genuinely exists, so the package is not speculative.
8. **Watch UI is two screens** — checklist list → item list + Run, so triggering
   N reminders is always a confirmed, deliberate act.
9. **Watch app is watch-Only in behaviour**: it never writes EventKit; all write
   access goes through the phone.
10. **Tooling**: `make watch-build` (`generic/platform=watchOS`),
    `scripts/run-watch.sh` (real watch via `devicectl`), `scripts/test.sh` runs
    `make build` + `make watch-build` + shellcheck.

## What We're NOT Doing

- No create/edit/delete of checklists on the watch; it only lists and runs them.
- No item-level check-off on the watch — the unit of action is the whole
  checklist.
- No dedicated "CheckStitch" reminders list; Inbox only.
- No standalone watch app (`WKWatchOnly = YES`) and no watch-only install story.
- No new iOS screens or navigation; `ContentView`/`EditChecklistView` keep their
  shape, gaining only persistence.
- No `CheckStitchCore` extraction of the iOS EventKit create path — the write
  stays in the iOS app; Core holds model + message contract only.
- No test targets (unit or UI), no `InMemoryEventStore`, no UI-test seeding.
- No duplicate-run dedupe — running a checklist twice creates duplicates.
- No deletion/cleanup of reminders, no watch sync of completion state.
- No changes to `run-devices.sh`'s iPhone/macOS behaviour.

## Open Risks

- **Real-watch `devicectl` install of a *companion* watch app is untested**
  (research "Open Areas"). The watch bundle normally reaches the watch via the
  paired iPhone; `scripts/run-watch.sh` may need `-allowProvisioningUpdates`,
  may need the iPhone app deployed first, and may hit `devicectl` error 4016
  (device offline / RDS off). Budget for a build/deploy debugging loop.
- **watchOS EventKit authorization on device** (`requestFullAccessToReminders`,
  `authorizationStatus`) is only proven on the watch simulator in SingleThread.
  The watch's list may be empty until Reminders access is granted on the watch
  itself — the UI must handle "no access".
- **WatchConnectivity reachability**: with `transferUserInfo` a run can be
  queued while the phone app is not running; the watch cannot distinguish
  "delivered" from "waiting". "Queued" must not be shown as success.
- **`CheckStitchCore` must build for iOS 18.7, watchOS 27.0 and macOS** (the iOS
  target still supports macOS); the package manifest platforms must match
  `IPHONEOS_DEPLOYMENT_TARGET = 18.7` / project-level `WATCHOS_DEPLOYMENT_TARGET = 27.0`
  (`project.pbxproj:173, :183`).
- **Hand-editing `project.pbxproj`** for a new target, product ref, embed phase
  and package dependency is error-prone; a malformed edit breaks every build.
  The file is JSON-ish and not covered by the gate beyond the build itself.
- **List-appearance latency**: the watch lists its cached set, which only
  updates on sync; a checklist created on the phone may not appear until the
  watch app is foregrounded and the context is refreshed.
- **`EKCADErrorDomain Code=1021`** (EventKit per-process connection cap) is a
  known hazard once more than one `EKEventStore` exists per process; keep a
  single store instance on the phone.