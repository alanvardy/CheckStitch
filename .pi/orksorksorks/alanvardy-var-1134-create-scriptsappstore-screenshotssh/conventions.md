# Conventions & Shared Facts

## Canonical commands
- Full gate: `bash scripts/test.sh` (AGENTS.md; `scripts/test.sh:40-132`).
- Builds: `make build` (iOS sim), `make build-mac` (unsigned), `make build-mac-signed` (signed, `-allowProvisioningUpdates`), `make watch-build` (generic watchOS sim), `make widget-build` (`Makefile:25-72`).
- Tests: `make test-unit` (macOS-hosted, fast), `make test-ui` (one XCTest smoke on resolved sim), `make test` = unit + ui (`Makefile:77-103`).
- Shell harness: `bash scripts/tests/run.sh` (`scripts/test.sh:121-123`).
- Lint: `shellcheck scripts/*.sh scripts/tests/*.sh` with `bash -n` fallback (`scripts/test.sh:125-130`); localization `bash scripts/l10n-check.sh`.
- Run: `make run`, `bash scripts/run-devices.sh`, `bash scripts/run-watch.sh`.

## Simulator/destination rules
- Destination precedence: explicit `SIM=` > worktree `.simulator_id` > shared `name=iPhone 17` (`Makefile:1-5`).
- Never leave a bare `name=` destination in a script (AGENTS.md; `AGENTS.md` simulator section).
- Sim resolution helper: `scripts/resolve-sim-udid.sh [--require-id] <destination|id=...>` (`:9-39`).
- Gate takes `${TMPDIR:-/tmp}/checkstitch-simulator.lock`, `LOCK_TIMEOUT` default 60, reaps stale holder PID, shuts down only the resolved UDID (`scripts/test.sh:47-103`).
- `.simulator_id` in this worktree: `EEC91D32-5F6F-4D1D-AF4D-1162665579F6`.

## Test-suite inventory
| Path | Covers | Gating |
|---|---|---|
| `CheckStitchTests/` (Swift Testing, macOS-hosted) | core models/store/codec/sync/settings/localization; includes `AppGroupTests.swift`, `SettingsBindingsTests.swift`, `LocalizationTests.swift`, `LocalizationFixtures.swift` | `make test-unit`, `platform=macOS`, `CODE_SIGNING_ALLOWED=NO` |
| `CheckStitchUITests/CheckStitchUITests.swift` | one XCTest smoke: launch + element existence + accessibility audit | `#if os(iOS)` around the audit; whole bundle compiles on macOS |
| `scripts/tests/run.sh` | shell-script behaviour with stubbed `xcrun/defaults/make/open/osascript`: resolver, gate preboot/lock/shutdown, run-watch, run-devices, macOS sandbox, warnings-as-errors legs, Info.plist, `bash -n` | run by gate unless `GATE_TESTS_SKIP=1` |

- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt into `@MainActor` (AGENTS.md).
- New user-facing string keys need all 6 languages plus a `LocalizationFixtures.requiredKeys` entry.

## Build/verify gotchas
- Warnings are errors in project-level Debug/Release configs (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, `GCC_TREAT_WARNINGS_AS_ERRORS=YES`); the shell harness pins the covered legs (`scripts/tests/run.sh:398-444`).
- `build-mac-signed`, `run-watch.sh`, `run-devices.sh` sit outside the enforced warnings-as-errors set (AGENTS.md).
- System has no GNU `timeout`/`nohup`; shell under the agent is fish (AGENTS.md / fish-shell skill).
- Scripts are `#!/bin/bash`, `set -euo pipefail`, mode `100755` (AGENTS.md).
- `PBXFileSystemSynchronizedRootGroup`: new files under `CheckStitch/` need no `project.pbxproj` edit (AGENTS.md).
- Xcode scheme `CheckStitch` is committed/shared, so `xcodebuild test` is deterministic (AGENTS.md).
- UI test is built and run in two phases (`build-for-testing` then `test-without-building`) (`Makefile:92-103`).

## Existing app seams (factual)
- No `ProcessInfo`/`CommandLine`/launch-argument code anywhere in app/Core/UI tests (Q4).
- Persisted preference keys: `appLanguage`, appearance mode, orientation, crash-reporting consent (Q4, Q6).
- Persistence: App Group `UserDefaults` key `checklists.v1`, JSON envelope version 6, plus iCloud KVS mirror (Q2).
- Language ids: `en, de, es, fr, ja, zh-Hans` + `.system` (Q6).
- UI test does `XCUIApplication().launch()` with no arguments (`CheckStitchUITests/CheckStitchUITests.swift:14-15`).
