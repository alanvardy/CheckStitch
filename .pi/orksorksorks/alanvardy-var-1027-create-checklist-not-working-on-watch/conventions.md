# Conventions — CheckStitch (VAR-1027 research appendix)

Factual build/test/verify reference for the repo. Source of authority: `AGENTS.md`
(project root), `Makefile`, `scripts/*.sh`, `CheckStitchCore/Package.swift`.

## Layout / structure
- `CheckStitch/` — thin app target (views + platform delegates only); `CheckStitchCore/`
  — local sources-only SPM package (models, EventKit seam, checklist creator, view model);
  `CheckStitchWatch/` — watchOS target (4 files: app entry, list, detail, `WatchSyncAdapter`).
- New files under `CheckStitch/` or `CheckStitchWatch/` need **no** `project.pbxproj`
  edit — the project uses `PBXFileSystemSynchronizedRootGroup`. `CheckStitchCore` has
  **no Tests/** dir; all unit tests live in the app-hosted `CheckStitchTests` target with
  `@testable import CheckStitchCore`, hosted on macOS.
- App Group entitlements: `CheckStitch/AppGroup.entitlements`
  (`group.app.alanvardy.CheckStitch`); `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id
  `app.alanvardy.CheckStitch`; KVS entitlement for macOS iCloud sync.
- Reference implementation for Reminders/EventKit: `/Users/vardy/dev/SingleThread`
  (`EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)`,
  `NSReminders*UsageDescription` keys; `GENERATE_INFOPLIST_FILE = YES`).

## Canonical commands
- `make build` — simulator build (`xcodebuild`, scheme `CheckStitch`).
- `make build-mac` — unsigned macOS compile leg (gate's platform check; no signing).
- `make build-mac-signed` — runnable macOS app, development-team signed (KVS entitlement
  embedded, iCloud sync works); needs `-allowProvisioningUpdates`; used by `run-devices.sh`.
- `make run` — build, boot/install/launch on a simulator (window pinned to resolved UDID).
- `make watch-build` — watchOS simulator compile of `CheckStitchWatch` against the same
  `CheckStitchCore` package, unsigned and sim-free.
- `make test-unit` — `CheckStitchTests` on `platform=macOS` with `CODE_SIGNING_ALLOWED=NO`
  (no sim, no signing). Fast pre-gate check.
- `make test-ui` — exactly one `CheckStitchUITests` smoke case via
  `build-for-testing` → `test-without-building` on the worktree's `.simulator_id`.
- `bash scripts/run-watch.sh` — build `CheckStitchWatch`, install + launch on the paired
  Apple Watch via `devicectl` (watch resolved by name to an identifier — never a bare
  name in a destination). Verifies build/install/launch only.
- `bash scripts/run-devices.sh` — install + launch on real devices (needs Developer Mode;
  prefers iPhone). Honours `SCHEME`/`BUNDLE_ID`/`CONFIGURATION`/`DERIVED_DATA` overrides;
  `RUN_MAC=1` adds the signed macOS leg.
- **The gate is `./scripts/test.sh`**: `make build` → headless pre-boot of the worktree
  simulator → `make test` → `make build-mac` → `make watch-build` →
  `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`,
  printing `gate: ok`. Workers verify with targeted checks only; the full gate runs once,
  by the parent, after all phases commit.

## Test-suite inventory (CheckStitchTests, Swift Testing, macOS-hosted; `@MainActor` opt-in)
- `WatchChecklistStoreTests.swift` (`@MainActor`, `FakeChecklistSyncTransport`): activation,
  context population (current/v2/malformed), run sends one `.runChecklist` + pendingRunID,
  rejected run, requestRefresh, activation refresh, field survival. Gaps: retry, view
  feedback, real WCSession.
- `ChecklistSyncCoordinatorTests.swift` (`SpyChecklistRunner` createReminders): start push,
  re-push on store change, known-ID creates once, **unknown-ID silent drop**, requestChecklists,
  activation seeding. Gap: pendingRun queue / error paths.
- `ChecklistSyncMessageTests.swift`: userInfo codec round-trips + rejection of unknown
  keys/types. Not `@MainActor`.
- `ChecklistCreatorTests.swift` (`@MainActor`, `SpyReminderCreator`): blank-skip, counts,
  permission/access/error outcomes, relative-date components.
- `EventKitReminderCreatorTests.swift`: crash-canary only (injected store, unsaved
  `EKReminder` dueDateComponents); no real EventKit API calls.
- `CheckStitchUITests/`: one XCTest smoke case (build-for-testing → test-without-building).
- Suite-wide: `#if os(macOS)` gating appears only in a few view tests
  (AboutViewTests:23, ViewRenderTests:27, ChecklistDetailViewTests, MacWindowFrameTests) —
  sync/creator suites are ungated. Test targets deliberately do **not** set
  `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with `@MainActor`. Platforms: unit tests run
  on `platform=macOS` without a simulator.
- Scripts' own shell tests: `scripts/tests/run.sh` stubs `xcrun`/`defaults`/`make`/`open`/
  `osascript` on PATH; asserts run-watch device resolution/install/launch argv, gate lock
  behavior, pbxproj sandbox scan.

## Build/verify gotchas
- Both real adapters (`PhoneSyncAdapter`, `WatchSyncAdapter`) live in app targets and are
  **never compiled into tests** — no test exercises real WCSession behavior; transport is
  always `FakeChecklistSyncTransport` (TestFixtures.swift:149-177).
- Simulator windows: the gate takes a bounded host lock
  (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`), pre-boots this worktree's `.simulator_id`
  headlessly between `make build` and `make test`, shuts down that exact UDID on exit;
  `LOCK_TIMEOUT` default 60 s; missing `.simulator_id` → skip, unresolvable → hard error;
  shutdown scoped to the resolved UDID only — never `all`/`booted`.
- Destination precedence (Makefile): explicit `SIM=` > this worktree's `.simulator_id` >
  shared default. Never leave a bare `name=` destination in a script — it selects a shared
  device and wedges parallel agents.
- `hx` panics without a TTY — use `git commit -m "..."` and `git -c core.editor=true
  rebase --continue`; stale `.git/index.lock` after a crashed git is safe to `rm`.
- Signing: values above are the working ones; do not re-derive the team from
  `~/Library/Developer/Xcode`. Add `-allowProvisioningUpdates` where the profile is absent.
- Sync/icon/render tickets cannot close on static evidence — verify on-device and state
  what the user should see (devicectl).
- Shell scripts: `#!/bin/bash` with `set -euo pipefail`, committed `100755`; keep plural
  `run-devices.sh` name (the `r` fish alias runs it).
- Subagent/tool preamble: the command tool runs fish — compound commands, `VAR=`, heredocs
  and loops fail; write `/tmp/x.sh` and run `bash /tmp/x.sh`; on `fish:` rejections stop
  and retry via `bash -c '...'`.

## Watch/phone sync facts Design/Plan rely on (from research.md)
- Watch "Sent" = `WCSession.transferUserInfo` accepted, not creation; no feedback channel
  exists back to the watch (`ChecklistSyncCoordinator` never calls `sendUserInfo`).
- Silent drop points: decode guard (`ChecklistSync.swift:19-31`), `onMessage` nil before
  `coordinator.start()` (`ChecklistSyncCoordinator.swift:34`), snapshot-ID guard (`:40`),
  discarded `ReminderRunOutcome` (`MyApp.swift:67` closure returns `Void`), `.permissionDenied`
  /`.destinationMissing` unlogged.
- Sends are dropped pre-activation (`WatchSyncAdapter.swift:28`); reliable refresh is the
  `onActivated` callback, not the `.task { requestRefresh() }` in the list view.
- Root cause is not yet located; distinguishing the drop points requires a device spike
  (real watch/phone via `bash scripts/run-watch.sh`) plus instrumentation of the phone
  receive path — codebase alone cannot decide.