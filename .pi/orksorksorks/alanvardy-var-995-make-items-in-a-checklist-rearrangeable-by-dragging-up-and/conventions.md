# Conventions

## Build / run / verify commands (from `Makefile` and `AGENTS.md`)

- **The gate is `bash scripts/test.sh`** (prints `gate: ok`). Full sequence: `make build` (simulator) → headless pre-boot of this worktree's `.simulator_id` UDID → `make test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`. Bounded host lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock` (`LOCK_TIMEOUT` default 60); quits `Simulator.app` once before the simulator-touching part; EXIT trap releases the lock and shuts down the resolved UDID (never `all`/`booted`).
- `make test` = `test-unit` + `test-ui` (Makefile `test` target).
- `make test-unit` — `xcodebuild -scheme CheckStitch -destination 'platform=macOS' ... CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` (macOS host, unsigned, no simulator boot). Fast loop: run this before the full gate.
- `make test-ui` — `build-for-testing` then `test-without-building -only-testing:CheckStitchUITests` on destination `$(SIM)`, i.e. this worktree's dedicated simulator — **never a bare `name=` destination** (bare names select a shared device and wedge parallel agents).
- `make build` — simulator build; `make build-mac` — unsigned macOS compile leg (headless); `make build-mac-signed` — signed/runnable macOS app (needs `-allowProvisioningUpdates`); `make watch-build` — watchOS simulator compile of `CheckStitchWatch` (unsigned, sim-free); `bash scripts/run-watch.sh` — install + launch on the paired watch via `devicectl` (resolve watch name to an identifier first).
- Destination precedence (Makefile:3-6): explicit `SIM=` > this worktree's `.simulator_id` > shared `platform=iOS Simulator,name=iPhone 17`.
- `make run` — build then `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'` (pins the window to the resolved UDID via `-CurrentDeviceUDID`; `Simulator.app` attaches a window to every device booted while alive — windows are expected, the gate's lock manages contention).
- Simulator-window ctx: the `com.apple.iphonesimulator AutoOpenDevice` preference is **ineffective** on this toolchain (Xcode 26.6 / iOS 27.0 spike) — the host lock is the mitigation.

## Test-suite inventory (`CheckStitchTests/`, macOS-hosted)

- XCTest style (`import XCTest`, `final class X: XCTestCase`, `@MainActor`):
  - `ChecklistStoreTests.swift` — store API, persistence-reload, debounce, stamps, apply/merge, tombstones; `@testable import CheckStitch` white-box; fresh per-test `UserDefaults` suite + `defer` cleanup (11-31); deterministic `Clock` (25); `textEditDelay: nil` opt-out except two debounce tests (20-22, 139, 159).
  - `ChecklistCodecTests.swift` — envelope round-trip, v1-migratable, unknown-version, unreadable-vs-unsupported, `isBlank`-less v1.
  - `CheckStitchUITests/CheckStitchUITests.swift` — the one UI XCTest smoke (`testLaunchAndAccessibilitySmoke`), accessibility identifiers + audit with `#if os(iOS)` split; run only via `make test-ui` on the worktree simulator.
- Swift Testing style (`import Testing`, `struct X`, `@Test`, `#expect`):
  - `ChecklistMergeTests.swift` — merge winner rules, order (local-first), tombstones, symmetry (arg-order swap), no-op; fixture builders `envelope()/checklist()/item()/tombstone()`.
  - `ChecklistItemTests.swift`, `ChecklistSyncServiceTests.swift` (uses `InMemoryChecklistSync` fake), `ChecklistSyncCoordinatorTests.swift`, `ChecklistSyncMessageTests.swift`, `WatchChecklistStoreTests.swift` (`FakeChecklistSyncTransport`), `UbiquitousChecklistSyncTests.swift` (construction/cancel canaries — no real KVS I/O on host), `ChecklistViewModelTests.swift`, `ChecklistCreatorTests.swift`, `ChecklistWidthTests.swift`, `EventKitReminderCreatorTests.swift`, `ViewRenderTests.swift`, `SmokeTests.swift`.
- Non-core suites in the same target: `AppearanceModeTests.swift`, `AppearanceModePreferenceTests.swift`, `BackgroundFadeTests.swift`, `BackgroundImageStoreTests.swift`, `BackgroundPhotoLayerTests.swift`, `CardPlateTests.swift`, `HarnessTests.swift`, `LocalizationTests.swift`, `MacWindowFrameTests.swift`, `SettingsBindingsTests.swift`.
- Fixtures: `TestFixtures.swift` (`InMemoryChecklistSync` 52, `InMemoryObservation`, `FakeChecklistSyncTransport`, `SpyReminderCreator`, `SpyChecklistRunner`, `makeItem`, `makeIsolatedDefaults`, `sharedTestEventStore`, `TestError`), `BackgroundTestFixtures.swift`, `LocalizationFixtures.swift`, `LocalizationTestHelpers.swift`.
- Platform gating: unit suites run `platform=macOS`; the UI smoke is simulator-only. Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`, so suites opt in with `@MainActor` (XCTest) or `@MainActor` on Swift Testing structs — never restore the app default there. Unit tests import `@testable import CheckStitchCore` (store suite also `@testable import CheckStitch`).

## Gotchas surfaced by research

- **IndexSet is exercised only as single-offset deletes** (`IndexSet(integer: N)` → `removeItems`, `ChecklistStoreTests.swift:68, 399-400`); multi-offset/move semantics have no test precedent.
- **Order-sensitive equality**: `contentEquals` (`Checklist.swift:160-166`) and `apply`'s `visibleChanged` (`ChecklistStore.swift:201`) compare arrays with `==` — item order counts, and a reorder changes both predicates.
- **Tombstone determinism**: merge sorts tombstones by key (`ChecklistMerge.swift:57-61`) so re-merging is a no-op — new merge output must stay deterministic or `apply` idempotence breaks.
- **Debounce**: per-keystroke text saves coalesce at 300 ms; structural edits save immediately and cancel the pending timer; `flushPendingSave()` runs on view disappear — a new structural mutation should follow the immediate-`save()` pattern (and cancel any queued text save, as `save()` already does at `ChecklistStore.swift:239-240`).
- **`onChange` suppression**: `save()` fires `onChange` unless `isApplyingRemote` (247) — remote-applied changes must not loop back into a push.
- **No `.onMove`/drag precedent**: zero grep hits for `onMove|onReorder|drag|reorder` in `*.swift`; the only edit-mode affordance is `.onDelete` (`ChecklistDetailView.swift:30-33`), and the items `ForEach` passes no explicit `id:` mapping (28).
- **KVS not exercisable on host**: sync tests use the `InMemoryChecklistSync` fake; `UbiquitousChecklistSyncTests` are canaries only.
- **Verse-style syntax**: production/test sources use indentation-based blocks, `guard/let/else`, `#expect`/`@Test`, `@Observable`, `$0`/`\.field` lambdas — copy existing shapes verbatim rather than writing brace-style Swift.
- Scripts: `#!/bin/bash` with `set -euo pipefail`, committed mode `100755`. `shellcheck` runs in the gate.