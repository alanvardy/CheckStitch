# Conventions

Shared factual appendix for Design/Structure/Plan. Source: research fan-out
(Q1-Q5) + targeted verification reads. Repo root =
`/Users/vardy/dev/alanvardy-var-1010-resolve-all-warnings`.

## Canonical commands

- **Gate**: `./scripts/test.sh` — `set -euo pipefail` (`scripts/test.sh:3`), order: `make build` → simulator lock + pre-boot (`scripts/test.sh:50-100`) → `make test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` (skip with `GATE_TESTS_SKIP=1`, `scripts/test.sh:117-119`) → shellcheck (fallback `bash -n`) → `echo "gate: ok"` (`scripts/test.sh:127`). Env overrides: `SIM`, `LOCK_TIMEOUT` (default 60), `GATE_TESTS_SKIP`.
- **Make legs** (`Makefile`):
  - `make build` — `xcodebuild -scheme CheckStitch -destination $(SIM) -configuration Debug -derivedDataPath DerivedData build` (`Makefile:18-21`)
  - `make test-unit` — `xcodebuild -scheme CheckStitch -destination 'platform=macOS' ... CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` (`Makefile:45-53`); `make test-ui` — `build-for-testing` then `-only-testing:CheckStitchUITests test-without-building` on `$(SIM)` (`Makefile:55-67`); `make test` = `test-unit test-ui` (`Makefile:59`)
  - `make build-mac` — macOS slice, unsigned, `CODE_SIGNING_ALLOWED=NO` (`Makefile:28-35`); `build-mac-signed` adds `-allowProvisioningUpdates` (`Makefile:36-38`)
  - `make watch-build` — `-scheme CheckStitchWatch -destination 'generic/platform=watchOS Simulator'` (`Makefile:47-53`)
  - `WATCH_SCHEME := CheckStitchWatch` (`Makefile:8`), `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, `CONFIGURATION := Debug`, `DERIVED_DATA := DerivedData`
- **CI**: `.github/workflows/dependabot-checks.yml` — dependabot PRs only (:17-19), runs the four make legs + `bash scripts/tests/run.sh` + shellcheck as separate steps (never `scripts/test.sh` itself); env `DEVELOPMENT_TEAM: ""`, `SIM: generic/platform=iOS Simulator` (:24-26).
- **No xcodebuild output capture exists anywhere** (gate, Makefile, CI all stream to console) and **no warning-as-error flags exist** (no `SWIFT_TREAT_WARNINGS_AS_ERRORS`/`SWIFT_SUPPRESS_WARNINGS`/`WARNING_CFLAGS` in `project.pbxproj`; `CheckStitchCore/Package.swift` has no `swiftSettings`).

## Test-suite inventory

| Path | Framework | Gating | Covers |
|---|---|---|---|
| `CheckStitchTests/ChecklistStoreTests.swift` | XCTest (`import XCTest` :1, `@testable import CheckStitch` :2, `import CheckStitchCore` :3; `@MainActor final class ...: XCTestCase` :5-6) | `make test-unit` (macOS, `CODE_SIGNING_ALLOWED=NO`) | ChecklistStore CRUD/ordering/move/create (§ uses `XCTAssertEqual`, `try? XCTUnwrap`, `XCTFail`) |
| `CheckStitchTests/WatchChecklistStoreTests.swift` | Swift Testing (`@testable import CheckStitchCore` :2, `import Foundation` :3, `import Testing` :4; `@MainActor struct` :5-6; `@Test`, `@Test(arguments:)` :194/:304, `#expect`, `try #require`) | same `make test-unit` leg | watch checklist run lifecycle, result/error mapping |
| `CheckStitchTests/ChecklistImportSessionTests.swift` | Swift Testing (`@testable import CheckStitch` :1, `import CheckStitchCore` :2, `import Foundation` :3, `import Testing` :4) | same `make test-unit` leg | JSON import/backfill/insert (`#expect(throws: ...)` :61/:78) |
| `CheckStitchUITests/CheckStitchUITests.swift` | XCTest, single case `testLaunchAndAccessibilitySmoke` | `make test-ui` (iOS sim via `build-for-testing` + `test-without-building`, `-only-testing:CheckStitchUITests`) | launch + accessibility audit; compiles only under `test-ui` (warning status unverified) |
| `scripts/tests/run.sh` | bash harness, not a test target | gate `scripts/test.sh:117-119` + CI step | gate/simulator/shell-script regression: resolve-sim-udid (5 cases), pre-boot/shutdown & lock semantics with stubbed `make xcrun defaults open osascript xcodebuild`, run-watch/run-devices argv assertions, macOS-sandbox pbxproj awk check (:307-330) |

- **Platform gating / actor isolation**: test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` in `project.pbxproj`; suites opt in per-suite with `@MainActor`. Never restore the app's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`/`SWIFT_APPROACHABLE_CONCURRENCY = YES` defaults (`project.pbxproj:524, 569, 695, 724`) on test targets (`project.pbxproj:595-622, 644-670`).
- **Determinism**: committed shared scheme `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme` — both testables `parallelizable="NO"` `skipped="NO"` (TestAction :26-59); per-leg `-only-testing:` pins one suite.
- **Swift Testing idioms**: unwrap-or-fail is `try #require(<throwing|optional>)` bound to `let` (ubiquitous: `LocalizationTests.swift:15,25,47,...`, `ChecklistSyncServiceTests.swift:144,183`, etc.); `#expect(...)` for asserts. XCTest suites may legitimately mix with Swift Testing in the *same* target.

## Gotchas surfaced by research

- **Gate's own `warning:` stderr lines** at `scripts/test.sh:65, :102, :124` will false-positive any naive log grep for compiler warnings — a warnings check must distinguish hand-written gate messages from `xcodebuild`/clang diagnostic lines.
- **AppIntents noise**: "Metadata extraction skipped, no AppIntents.framework dependency found" is toolchain output (its literal is absent from repo files); recorded in 3 of 4 legs (large.md:16-18) and up to 11× across a full gate (`var-1027/done.md:4`) — pre-existing, benign, must be scoped out.
- **Warning counting vs sites**: the recon "8× redundant #require / 8× unused init" double-counts each macro site (diagnostic + produced-annotation); current source has exactly **4** `try #require(store.run(...))` sites (`WatchChecklistStoreTests.swift:59, 142, 158, 183`) and **4** unused `let` sites (`ChecklistImportSessionTests.swift:82, 88`; `ChecklistStoreTests.swift:1295, 1296`).
- **`ChecklistStore.swift` has no `refresh()`** — the only app-source discard-result warning site is `ContentView.swift:100` (`.refreshable { await syncService.refresh() }`, callee `ChecklistSyncService.swift:77`).
- **Shell harness hygiene**: gate children must run with `GATE_TESTS_SKIP=1` + stubbed `make` (no recursion, no real builds); lock tests use a private `TMPDIR` so the live host lock is never touched; the harness asserts `shutdown|boot` is never `(all|booted)`.
- **Simulator discipline**: pre-boot/shutdown scoped to the resolved UDID only (`scripts/test.sh:98-100, 96-106`); missing `.simulator_id` → skip; unresolvable id → hard error; lock is `${TMPDIR:-/tmp}/checkstitch-simulator.lock`, reaped when the recorded PID is dead.