# Conventions & Factual Appendix — CheckStitch

Dense reference for Design/Structure/Plan. All paths relative to repo root
`/Users/vardy/dev/alanvardy-var-1163-scaling-bug` unless absolute.

## Canonical commands
- **Gate**: `./scripts/test.sh` — `make build` (simulator) → headless pre-boot of
  this worktree's `.simulator_id` → `make test` → `make build-mac` →
  `make watch-build` → `scripts/tests/run.sh` → `shellcheck scripts/*.sh
  scripts/tests/*.sh`; prints `gate: ok` (repo `AGENTS.md`).
- **Fast unit leg**: `make test-unit` — `CheckStitchTests` on `platform=macOS`,
  `CODE_SIGNING_ALLOWED=NO`. Use before the full gate.
- UI smoke: `make test-ui` (`CheckStitchUITests`, build-for-testing → test-without-building).
- Builds: `make build`, `make build-mac` (unsigned macOS compile leg),
  `make build-mac-signed`, `make watch-build` (watchOS compile), `make run`,
  `make appstore-screenshots`.
- Test-only scaling entry point: `ChecklistCreator.create(from:multiple:)`
  (`CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift:95`), described
  in tests as "Path B".
- Warnings-as-errors in project Debug + Release
  (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, `GCC_TREAT_WARNINGS_AS_ERRORS=YES`);
  `CheckStitchCore` not separately enforced.
- Destination precedence: explicit `SIM=` > this worktree's `.simulator_id` >
  shared default (documented in `Makefile`). Never leave a bare `name=`
  destination.

## Test-suite inventory
All unit suites are Swift Testing (`@Test`, `#expect`) and `@testable import
CheckStitchCore`, unless marked XCTest. `@MainActor` is opted-in per suite.
| File | Covers |
|---|---|
| `CheckStitchTests/ChecklistCreatorTests.swift` | Resolver grammar + `ChecklistScaling.resolve` (`:198-231`), `multipleOneIsAFastPath` (`:214`), title numbering, "Path B" create |
| `CheckStitchTests/ChecklistRemindersTests.swift` | Funnel create; scaling title/description (`:566`), stored-text-not-rewritten (`:585`), override-scales-this-run-only (`:675`) |
| `CheckStitchTests/ChecklistRunViewModelTests.swift` | Run VM `fixed`/`prompt`/cancel/override (`:352-400`) |
| `CheckStitchTests/RunChecklistIntentTests.swift` | App Intent multiple resolution + prompter paths (`:246-561`) |
| `CheckStitchTests/ScalingTests.swift` | `Scaling.number`/`.toggled()`/`.clamped()`/`.displayNumber`/`.isPrompt` (`:6-29`) |
| `CheckStitchTests/PromptScalingSheetTests.swift` | Sheet input validation (`:7-18`) |
| `CheckStitchTests/ChecklistDetailViewTests.swift` | Badge visibility, `multipleRange == 1...99` (`:188-228`) |
| `CheckStitchTests/ChecklistCodecTests.swift` | XCTest; envelope scaling encode/decode, legacy/unknown mode, clamp (`:589-663`) |
| `CheckStitchTests/ChecklistExportTests.swift` / `ChecklistImportSessionTests.swift` / `UbiquitousChecklistSyncTests.swift` | Export/import/sync scaling round-trips (no resolver assertions) |
| `CheckStitchTests/LocalizationFixtures.swift` | `requiredKeys` pinned catalog keys (`:34,56,57,89,99,100,102,178`); exclusions `:226-227` |
| `CheckStitchTests/TestFixtures.swift` | `makeItem`, `makeIsolatedDefaults` (`:17`), `SpyReminderCreator` (`:29`), `SpyReminderDestination` (`:52`), `FakeScalingPrompter` (`~:155`), `TestError.boom` |
| `CheckStitchUITests/CheckStitchUITests.swift` | Single XCTest launch/accessibility smoke + UI-testing seam cases; **no scaling case** |

Shell tests: `scripts/tests/run.sh` (stubs `xcrun`/`defaults`/`make`/`open`/`osascript`
on `PATH`); included by the gate.

## Localization
- User-facing strings live in `CheckStitch/Localizable.xcstrings`; a new key
  needs all 6 languages (en/de/es/fr/ja/zh-Hans) + a `LocalizationFixtures.requiredKeys`
  entry. Run `scripts/l10n-check.sh` first (see `localization` skill).
- Scaling strings: help footer `Localizable.xcstrings:3079`, factor hint `:3038`.
- `.lproj` holds only `InfoPlist.strings`.

## Layout
- `CheckStitch/` — thin app target (views + platform delegates); new files need
  no `project.pbxproj` edit (`PBXFileSystemSynchronizedRootGroup`).
- `CheckStitchCore/` — local sources-only SPM package: models, EventKit seam,
  checklist creator/reminders funnel, view model, App Intent.
- `CheckStitchWatch/` — Watch target (compiles same `CheckStitchCore`).
- Entitlements: App Group `group.app.alanvardy.CheckStitch`; team `6NWX2DHB9Q`;
  bundle id `app.alanvardy.CheckStitch`.

## Gotchas
- Sync/icon/render tickets cannot close on static evidence; verify on target
  (see `devicectl`).
- Simulator windows: why they appear and lock protocol (see `simulator` skill).
  Gate takes `${TMPDIR:-/tmp}/checkstitch-simulator.lock`.
- `swiftui-sdk` skill: the compiler is the oracle for SwiftUI API questions.
- Step artifacts under `.pi/orksorksorks/<branch>/` are committed in this repo.
