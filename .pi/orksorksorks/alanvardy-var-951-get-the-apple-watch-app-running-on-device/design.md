# Design Discussion

## Current State

**Branch/base drift (must be resolved first).** This worktree `HEAD` (`0bbb6fb`) is
based on `326b861` — an old `main`. Current `main` has since gained the
persistence layer, the `CheckStitchCore` package, test targets and a `make test`
gate, and its `AGENTS.md`/gate differ from this branch's rewritten `AGENTS.md`.
The artifacts in this directory (`research.md` included) describe the old
two-file app and must be read as **historical**, not as the code we build on.

**Current `main` (the real base):**
- Model + persistence live in the app target: `CheckStitch/Checklist.swift`
  (`Checklist`, `ChecklistItem`, `ChecklistEnvelope`, `ChecklistCodec`,
  versioned, refuses to clobber newer payloads), `CheckStitch/ChecklistStore.swift`
  (`@Observable`, `UserDefaults` key `checklists.v1`, debounced text saves),
  `CheckStitch/AppGroup.swift` (`group.app.alanvardy.CheckStitch`, falls back to
  `.standard`). `AppGroup.swift` already says the group is "shared with the
  planned watch app (VAR-963)".
- Screens: `CheckStitch/ContentView.swift` (multi-checklist list + create +
  per-row reminder button), `CheckStitch/ChecklistDetailView.swift`,
  `CheckStitch/SettingsView.swift`; `CheckStitch/MyApp.swift` owns
  `@State ChecklistStore`.
- Reminder write path: `CheckStitch/ChecklistReminders.swift::create(from:)` —
  `EKEventStore()` → `requestFullAccessToReminders()` → one `EKReminder` per
  non-blank item with `calendar = defaultCalendarForNewReminders()` →
  `save(commit: true)`.
- `CheckStitchCore/` SPM package (`Package.swift`: `.iOS("18.7")`, `.macOS("27.0")`):
  `ChecklistItem` (a **second** `ChecklistItem`, `Identifiable/Equatable/Sendable`
  + `isBlank`), `ChecklistCreator`, `ReminderCreating`/`EventKitReminderCreator`,
  `ChecklistViewModel`, `AppEnvironment`, `AppearanceMode`, `ChecklistWidth`.
  The app target links it (`project.pbxproj:115-116`, `:60`); tests import it.
  Note: `ChecklistViewModel`/`ChecklistCreator` are exercised by
  `CheckStitchTests` but are **not** wired into the store-based `ContentView` —
  a pre-existing mid-refactor duplication.
- Tests/gate: `CheckStitchTests` (Swift Testing, macOS-hosted, `@testable import
  CheckStitchCore`) + `CheckStitchUITests` (one XCTest smoke); `scripts/test.sh` =
  `make build` + `make test` (`test-unit` on `platform=macOS`
  `CODE_SIGNING_ALLOWED=NO`, `test-ui` on `.simulator_id`) + `make build-mac` +
  `shellcheck`. **There is no `swift test` path and no `CheckStitchCore/Tests`.**
- No watch target, no watch sources, no watch build/run tooling anywhere.
  Destination precedence: `SIM=` > `.simulator_id` > shared default (`Makefile:4-9`).

**Reference:** `/Users/vardy/dev/SingleThread` — `SingleThreadWatch` target
(`SingleThread.xcodeproj/project.pbxproj:940-1016`), companion embedding
(`:69-75`, `:592-597`), read-only watchOS EventKit
(`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:34-37`),
`WatchAppViewModel.swift` + `WatchReminderView.swift` composition shell.
Real watch present: `Alan's Apple Watch` (`00008301-209B793C010BC02E`, paired,
available). No repo installs a **watch** bundle on real hardware yet.

## Desired End State

`CheckStitch` remains the **authoring and EventKit surface**. A new **companion
watch app** (`CheckStitchWatch`, `WKWatchOnly = NO`, embedded in
`CheckStitch.app`) is a **pure client**: it holds no EventKit code and requests no
Reminders permission. The phone syncs its persisted checklist set to the watch
over WatchConnectivity; the watch lists checklists, shows a checklist's items
read-only, and offers exactly one action — **"Create reminders"** — which sends a
run request to the phone. The phone performs the existing one-reminder-per-item
Inbox write.

Correct means, verifiable on the real watch:

1. `make build` (iOS), `make build-mac`, `make watch-build`
   (`generic/platform=watchOS`) and `./scripts/test.sh` all pass.
2. `bash scripts/run-watch.sh` installs and launches `CheckStitchWatch` on
   `Alan's Apple Watch`.
3. A checklist created/edited on the iPhone appears in the watch's list after it
   is running (pushed via `updateApplicationContext`).
4. Tapping that checklist on the watch shows its items, and "Create reminders"
   produces one Reminder per non-blank item in the Inbox, observable on the phone.
5. The watch creates no reminders any other way, edits nothing, and reads no
   EventKit.

## Patterns to Follow

- **Watch target recipe** — copy SingleThread's watch settings
  (`SingleThread.xcodeproj/project.pbxproj:940-1016`): `SDKROOT = watchos`,
  `SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `TARGETED_DEVICE_FAMILY = 4`,
  `SKIP_INSTALL = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
  `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitch.watchkitapp`,
  `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, `CODE_SIGN_STYLE = Automatic`,
  `GENERATE_INFOPLIST_FILE = YES`, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- **Companion embedding** — "Embed Watch Content" copy phase
  (`dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`, iOS platform filter) + a
  `PBXTargetDependency` (`pbxproj:69-75`, `:592-597`), with
  `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = app.alanvardy.CheckStitch`,
  `INFOPLIST_KEY_WKWatchOnly = NO` and `INFOPLIST_KEY_CFBundleDisplayName`
  (SingleThread `pbxproj:950-952`).
- **Source inclusion** — add `CheckStitchWatch/` as a
  `PBXFileSystemSynchronizedRootGroup` referenced by the watch target's
  `fileSystemSynchronizedGroups` (SingleThread `pbxproj:126-130`, `:328-330`);
  never hand-list watch files in a build phase. Note the CheckStitch project uses
  stable synthetic object IDs (`0000000000000000000000NN`) — follow that scheme.
- **Link `CheckStitchCore` into the watch target** — add a
  `PBXBuildFile`/Frameworks entry + `packageProductDependencies` entry reusing
  product ref `000000000000000000000031` (`project.pbxproj:10-12`, `:115-116`).
- **Signing split** — watch configs get **no** `CODE_SIGN_ENTITLEMENTS`
  (team-based automatic signing, as in SingleThread); the iOS target keeps
  `[sdk=iphoneos*]`/`[sdk=iphonesimulator*]` → `CheckStitch/AppGroup.entitlements`.
  On a machine without the profile, add `-allowProvisioningUpdates`.
- **Reminder creation** — reuse `CheckStitch/ChecklistReminders.swift::create(from:)`
  (`EKReminder` → `defaultCalendarForNewReminders()` → `save(commit: true)`,
  blank titles skipped). It runs **on the phone only**.
- **@MainActor + SwiftUI shell** — watch entry `@main struct …App` building a
  `WindowGroup`, state in `@MainActor @Observable` objects, views switching on
  state: `SingleThreadWatch/SingleThreadWatchApp.swift:3-15`,
  `WatchReminderView.swift:47-63`.
- **Scripts** — `#!/bin/bash`, `set -euo pipefail`, mode `100755`; resolve
  destinations to IDs (`…,id=<UDID>`; watch sim via
  `xcrun simctl list devices available`), never a bare `name=`
  (`scripts/run-simulator.sh`, `scripts/run-devices.sh`).
- **Testable logic** lives in `CheckStitchCore` and is covered by Swift Testing
  suites in the existing app-hosted `CheckStitchTests` (`@testable import
  CheckStitchCore`) — the repo's actual convention on `main`.

Patterns found in research that must **not** be followed:

- **`#if os(watchOS)` branches threaded through a shared store** — SingleThread
  compiles EventKit writes in/out inside its package. CheckStitch keeps EventKit
  entirely on the phone; the watch has no EventKit import at all.
- **watch test targets / `InMemoryEventStore` / `--ui-testing` seeding** —
  SingleThread's seams exist because it has watch test targets; we do not add any
  (new pure logic is tested through `CheckStitchTests`).
- **The branch's rewritten `AGENTS.md` claims** (`FileChecklistStore`,
  `swift test --package-path CheckStitchCore`, `CheckStitchCore` owning
  `Checklist`) — none are true on `main`; do not design against them.
- **A bare `name=` watch destination** — selects a shared simulator and wedges
  parallel agents (`conventions.md`, `Makefile:4-9`).

## Design Decisions

1. **Rebase onto current `main` first** — the watch-ready persistence (`AppGroup`,
   `ChecklistStore`, `ChecklistCodec`) and the `CheckStitchCore` seam already
   exist there; building on the stale base would re-port them and conflict.
   Reconcile `AGENTS.md`/artifacts afterwards.
2. **Companion watch app, not standalone** — `WKWatchOnly = NO`, embedded in
   `CheckStitch.app`, `WKCompanionAppBundleIdentifier` = the iOS bundle id; the
   only precedent that works and the only way WatchConnectivity is available.
3. **The watch is a pure client** — no `import EventKit`, no Reminders usage
   description/permission on the watch, no writes of any kind on the watch. All
   EventKit stays on the phone.
4. **Phone is the source of truth; WatchConnectivity is the transport.**
   `updateApplicationContext([checklists: Data])` carries the `ChecklistEnvelope`
   (latest-state); `transferUserInfo([runChecklist: UUID])` carries the run
   trigger (queued command) and `transferUserInfo([requestChecklists: true])`
   lets a cold-launched watch ask the phone to re-push.
5. **Move the shared model into `CheckStitchCore`** — relocate `Checklist`,
   `ChecklistItem`, `ChecklistEnvelope`, `ChecklistCodec` from
   `CheckStitch/Checklist.swift` into the package, and **merge the duplicate
   `ChecklistItem`** (the app's `Codable/Hashable` shape plus Core's `isBlank`/
   `Sendable`). `ChecklistStore` and the watch both import the package; the watch
   decodes the identical envelope. The WC key names and the run-request payload
   live in a new `CheckStitchCore` type so they are unit-testable.
6. **The watch has one action: create reminders from a checklist.** List →
   read-only item list → a single "Create reminders" button. No per-item
   check-off, no create/edit/delete, no completion sync. *(The item detail screen
   exists so a tap cannot silently write N reminders and so task.md's "read items"
   holds; if you want literal tap-to-run, delete the detail screen — see Open
   Risks.)*
7. **Reuse the existing phone write path** — on receiving a run request the phone
   looks the checklist up in `ChecklistStore` and calls
   `ChecklistReminders.create(from:)`. Do **not** introduce a second creation
   implementation; the pre-existing `ChecklistCreator`/`ChecklistReminders`
   duplication is left as-is.
8. **Tooling**: `make watch-build` (`generic/platform=watchOS`, scheme
   `CheckStitchWatch`) and `scripts/run-watch.sh` (real watch via `devicectl`
   install + `process launch`). Extend `scripts/test.sh` with `make watch-build`;
   keep `make build` / `make test` / `make build-mac` / shellcheck untouched.
9. **No new test target.** New pure logic (envelope encode/decode across the
   WC boundary, run-request parsing, the watch's checklist store) goes in
   `CheckStitchCore`/watch-shell types and is tested from `CheckStitchTests`.
   EventKit and `WCSession` adapters stay thin and are verified manually.
10. **Package platforms** — add `.watchOS("27.0")` to
    `CheckStitchCore/Package.swift` to match the project-level
    `WATCHOS_DEPLOYMENT_TARGET = 27.0` (`project.pbxproj:331`), and ensure the
    package still builds for iOS/macOS (the app target ships a macOS slice,
    `make build-mac`).

## What We're NOT Doing

- No check-off, completion state, or progress on the watch.
- No create/edit/delete/rename of checklists or items on the watch.
- No EventKit code, Reminders permission, or reminder reads on the watch.
- No dedicated "CheckStitch" reminders list — Inbox via
  `defaultCalendarForNewReminders()` stays.
- No standalone watch app (`WKWatchOnly = YES`) and no watch-only install story.
- No new iOS screens or navigation changes beyond what wiring sync requires.
- No item→`EKReminder` identity mapping, no duplicate-run dedupe (running twice
  creates duplicates), no reminder deletion/cleanup.
- No resolution of the pre-existing `ChecklistViewModel`/`ChecklistCreator` vs
  `ChecklistStore`/`ChecklistReminders` duplication.
- No new watch unit/UI test target, no `InMemoryEventStore`, no `--ui-testing`
  seeding.
- No changes to `run-devices.sh` / `run-simulator.sh` iPhone/macOS behaviour.

## Open Risks

- **Real-watch `devicectl` install of a companion watch bundle is untested**
  (research "Open Areas"). Companion watch apps normally reach the watch via the
  paired iPhone; `run-watch.sh` may need the iPhone app installed first, may need
  `-allowProvisioningUpdates`, and may hit `devicectl` error 4016 (offline / RDS
  off). Budget a build/deploy debugging loop and treat the script as the
  riskiest deliverable.
- **Hand-editing `project.pbxproj`** for a target, product ref, embed phase,
  dependency, synchronized group, package link and shared scheme is error-prone;
  a malformed edit breaks every target and the gate itself is the only detector.
- **WatchConnectivity reachability** — `updateApplicationContext` only reaches the
  watch while the phone app has been run and the watch app is active; a
  cold-launched watch starts empty until the re-push round-trips. The list may be
  stale.
- **Queued runs** — `transferUserInfo` queues while the phone app is not running,
  so the watch cannot distinguish "sent" from "executed". Do not show success
  prematurely (a "sent" state is the honest maximum).
- **`updateApplicationContext` payload size** (~65 KB) — checklist sets with many
  items could exceed it; if so, fall back to `transferUserInfo` for the payload.
  Watch for it, do not over-engineer now.
- **UX decision 6 is the one ambiguous point** — if "tap the checklist" is meant
  literally (tap = run, no detail screen), the watch is even smaller; confirm
  before planning.
- **Rebase conflicts** in `Makefile`, `scripts/test.sh`, `AGENTS.md` and the
  step artifacts against current `main`.
- **`EKCADErrorDomain Code=1021`** (EventKit per-process connection cap) remains a
  hazard if the sync path ever constructs a second `EKEventStore`; keep one.
