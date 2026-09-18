# Conventions — shared factual appendix for Design / Structure / Plan

Repo root below: `/Users/vardy/dev/alanvardy-var-1023-import-checklists-through-sharesheet/`. Base paths: app target `CheckStitch/`; core package `CheckStitchCore/Sources/CheckStitchCore/`; unit tests `CheckStitchTests/`; UI smoke `CheckStitchUITests/`; scripts `scripts/`.

## Canonical commands (from `Makefile`, `scripts/`, AGENTS.md)
- **Full gate**: `bash scripts/test.sh` — the official gate, prints `gate: ok`. Order: disk-clean → sim pre-boot (this worktree's `.simulator_id`, bounded `checkstitch-simulator.lock`, lone EXIT trap, scoped UDID shutdown) → `make build` (iOS sim) → `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → shellcheck → `gate: ok`.
- **Fast iteration**: `make test-unit` (CheckStitchTests, `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, `-only-testing:CheckStitchTests`) — run before the full gate.
- **UI smoke**: `make test-ui` — exactly one `CheckStitchUITests` XCTest case via `build-for-testing` → `test-without-building` on this worktree's `.simulator_id` simulator.
- **Compile legs**: `make build` (iOS sim), `make build-mac` (unsigned macOS), `make build-mac-signed` (team-signed, needs `-allowProvisioningUpdates`), `make watch-build` (watchOS, unsigned, sim-free), `make run` (build + boot/install/launch on sim).
- **Devices/watch**: `bash scripts/run-devices.sh` (real iPhone/host Mac, `RUN_WATCH=0` skips watch), `bash scripts/run-watch.sh` (paired Apple Watch; resolves name→identifier, never a bare name).
- **Warnings gates**: `WARNINGS_AS_ERRORS` (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`) enforced on build/build-mac/watch-build/test legs; `scripts/tests/run.sh` pins the per-leg list. `build-mac-signed`, `run-watch.sh`, `run-devices.sh` are outside enforcement.
- **Simulator**: tests boot this worktree's `.simulator_id` headless; `make run` requests its window explicitly pinned to the resolved UDID. Never leave a bare `name=` destination in a script (shared default wedges parallel agents). Expectation: a Simulator.app window may appear during `make test` / `make run`.
- **Scripts**: `#!/bin/bash`, `set -euo pipefail`, committed mode `100755`. Keep the plural `run-devices.sh` name.

## Test-suite inventory
| Suite (file) | Framework / gating | Covers |
| --- | --- | --- |
| `CheckStitchTests/ChecklistCodecTests.swift` | XCTest `final class`, `@MainActor` (class-level) | codec classify (v1-4 byte samples), envelope round-trip, order/field-clocks round-trip |
| `CheckStitchTests/ChecklistExportTests.swift` | XCTest `@MainActor` | export round-trip, priority, empty selection, filename regex/default/determinism, FileDocument bytes |
| `CheckStitchTests/ChecklistImportSessionTests.swift` | Swift Testing `@Test`/`#expect`, `@MainActor` | non-conflict insert, conflict pending, unsupportedVersion/unreadable errors, migratable, 3 decisions, re-import, priority |
| `CheckStitchTests/ChecklistImportExportViewModelTests.swift` | Swift Testing `@MainActor` | export selection→document, read/format failures, FIFO conflict queue (`decide` + `await Task.yield()`) |
| `CheckStitchTests/ChecklistCreatorTests.swift`, `ChecklistRemindersTests.swift`, `EventKitReminderCreatorTests.swift`, `EventKitReminderDestinationTests.swift`, `ReminderListsSnapshotTests.swift`, `ChecklistStoreTests.swift`, `ListChecklistsIntentTests.swift`, `RunChecklistIntentTests.swift`, `ChecklistMergeTests.swift`, `ChecklistItemTests.swift`, `ChecklistItemDateTests.swift`, plus ~45 more | Swift Testing, `@MainActor` on EventKit/view-model touching suites | per-component behaviour |
| `CheckStitchUITests/CheckStitchUITests.swift` | XCTest, single smoke `testLaunchAndAccessibilitySmoke`, `@MainActor`, `#if os(iOS)` audit categories | app launch/accessibility |

Notes:
- Unit suites import `@testable import CheckStitchCore`; UI smoke stays XCTest.
- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with `@MainActor` — never restore the app's default there.
- `@Test(arguments:)` is used in some suites (`ChecklistItemTests.swift:14,19,...`, `ChecklistItemDateTests.swift:22`, `ChecklistCreatorTests`, etc.) but NOT in the four codec/export/import-session/view-model suites.
- Fakes live in one file: `CheckStitchTests/TestFixtures.swift` (e.g. `sharedTestEventStore`); one-test-process-at-a-time for simulator-touching suites.

## Build / verify gotchas
- **New files under `CheckStitch/` need no `project.pbxproj` edit** (`PBXFileSystemSynchronizedRootGroup`); add Swift files and rebuild.
- **`GENERATE_INFOPLIST_FILE = YES`** on this project — the `NSReminders*UsageDescription` keys pattern (see reference impl `/Users/vardy/dev/SingleThread`) is required; do not drop infoplist generation.
- **Warnings fail the gate** on compiling legs — run `make build` / `make test-unit` (compiler is the oracle) instead of SDK-probing (see `swiftui-sdk` skill); SwiftUI API verification is by compiling, not by mining `.swiftinterface` files.
- **Simulator**: bounded host lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock`; shutdown scoped to resolved UDID only, never `all`/`booted`; missing `.simulator_id` → skip, unresolvable present `.simulator_id` → hard error.
- **Signing**: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch` (in `CheckStitch/AppGroup.entitlements`, incl. KVS `com.apple.developer.ubiquity-kvstore-identifier`). macOS slice signs with the same team; unsigned `build-mac` exists so the gate stays provisioning-free. Do not re-derive the team from `~/Library/Developer/Xcode`.
- **Never push directly to main**; PRs merge with `--rebase`. Use `git commit -m` (hx panics without TTY).
- **`edit` tool**: one top-level `path` per call; `oldText` must be byte-exact from `read`; disjoint edits per call.

## Import/creation seam facts the phases will reuse (from research)
- Wire format: JSON `ChecklistEnvelope` v4; `ChecklistCodec.classify` returns `.loaded/.migratable(1-3)/.unsupportedVersion/.unreadable` (`Checklist.swift:395-447`).
- File reception today is SwiftUI `.fileImporter(allowedContentTypes: [.json])` → `importFile(at: url)` with security-scoped read (`ContentView.swift:171-183`; `ChecklistImportExportViewModel.swift:67-85`).
- Import writes fresh local identity (new UUIDs, revision 1, drop `destinationListIdentifier`) and resolves name conflicts via FIFO + `replace/keepBoth/keepExisting` (`ChecklistImportSession.swift`; `ChecklistStore.swift:181-220`).
- Reminders creation: `ChecklistReminders.create(from:targeting:)` resolves `destinationListIdentifier` before any create; drops blank titles, applies `ChecklistTitleNumbering`, maps description→notes, priority raw 0/9/5/1, relativeDate→date-only dueDate (`CheckStitch/ChecklistReminders.swift`; `CheckStitchCore/.../ChecklistCreator.swift`, `ReminderDestinationTargeting.swift`, `ChecklistItemPriority.swift`).
- No OS file-receive or share-target seam exists (no `onOpenURL`/`CFBundleURLTypes`/`application(_:open:)`/`UTType`); the app's only OS entry surface is Siri/Shortcuts AppIntents (`CheckStitch/Intents/`).