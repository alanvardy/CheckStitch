# Conventions

Shared factual appendix for downstream steps (Design / Structure / Plan).
Paths relative to repo root. Prefer these references over re-reading source.

## Canonical commands

| Purpose | Command | Notes |
| --- | --- | --- |
| Full gate | `./scripts/test.sh` | `make build` (sim) → headless pre-boot of worktree sim → `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`; prints `gate: ok` (`scripts/test.sh:1-8`, `AGENTS.md:35`) |
| Fast unit | `make test-unit` | `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO` (no sim, no signing) (`Makefile:81`) |
| Sim build | `make build` | simulator build, scheme `CheckStitch` (`Makefile:25`) |
| macOS compile | `make build-mac` | unsigned, provisioning-free, gate platform leg (`Makefile:38`) |
| macOS signed | `make build-mac-signed` | dev team, App Group entitlements, KVS (`Makefile:48`); outside enforced warnings set |
| watch compile | `make watch-build` | watchOS sim compile of `CheckStitchWatch` (`Makefile:58`) |
| widget compile | `make widget-build` | (`Makefile:67`) |
| UI smoke | `make test-ui` | one `CheckStitchUITests` case via build-for-testing on `.simulator_id` (`Makefile:92`) |
| localization | `bash scripts/l10n-check.sh` | Python mirror of `LocalizationTests`; prints `l10n-check: ok` |
| run on sim | `make run` | builds, boots/installs/launches; pins resolved UDID (`Makefile:74`) |
| run on devices | `bash scripts/run-devices.sh` | real device + host Mac + paired watch (`RUN_WATCH=0` skips) |

- Warnings-as-errors: `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` /
  `GCC_TREAT_WARNINGS_AS_ERRORS=YES` in project-level Debug+Release
  (`CheckStitch.xcodeproj/project.pbxproj`); enforced in gate legs
  `build`, `test`, `build-mac`, `watch-build`, not in
  `build-mac-signed`/`run-watch.sh`/`run-devices.sh`. Pinned by
  `scripts/tests/run.sh` (`warnings_as_errors_reaches_compiling_legs`).
- Destination precedence (`Makefile`): explicit `SIM=` > this worktree's
  `.simulator_id` > shared default. Never a bare `name=` destination.

## Test-suite inventory

Test target `CheckStitchTests` (Swift Testing unless noted; `@testable import CheckStitchCore`).
Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` — suites opt in
with `@MainActor` (`AGENTS.md`).

| Suite / file | Covers | Style / gating |
| --- | --- | --- |
| `ChecklistCodecTests.swift:5-16` | v3 order keys / `orderRevision` / `orderModifiedAt` round-trip; multiple encode/clamp `:520-548` | legacy XCTest `final class`, `@MainActor` |
| `ChecklistStoreTests.swift` | store setters, save, duplicate/fresh-copy, import | legacy XCTest `@MainActor` |
| `ChecklistCreatorTests.swift:198-229` | `ChecklistScaling.resolve` (multiple:1 identity `:214-215`) | Swift Testing |
| `ChecklistRemindersTests.swift:563-592` | reminders create incl. `multiple` | Swift Testing |
| `ChecklistRunViewModelTests.swift:7,49,63` | run flow, `@Test(arguments:)` table | Swift Testing, `@MainActor` |
| `RunChecklistIntentTests.swift:8-12` | intent perform/validation/dialog | Swift Testing, `@MainActor` |
| `CreateChecklistIntentTests.swift` | create intent | Swift Testing |
| `ListChecklistsIntentTests.swift` / `ChecklistEntityQueryTests.swift` | intent entity query | Swift Testing |
| `ChecklistDetailViewTests.swift:1-19` | detail-view value via `String(describing:)`; scaling badge/range `:191-221`; macOS branches `:72,165,181,207,277,299,315,350` | Swift Testing, `@MainActor`, `#if os(macOS)` |
| `ChecklistMergeTests.swift` | LWW merge field set | Swift Testing |
| `UbiquitousChecklistSyncTests.swift:23-40` | sync wins carry `multiple` | Swift Testing |
| `ChecklistExportTests.swift:23,100-125` | export round-trip / `multiple` clamp | Swift Testing |
| `ChecklistImportSessionTests.swift:253-267` | import clamp | Swift Testing |
| `LocalizationTests.swift` | catalogs parse/en, 6 langs `:22-28`, required keys `:34-41`, Watch keys `:46-51`, canary `:56-64` | Swift Testing |
| `ColorCrossPlatformTests.swift:5,15` | cross-platform colors | `#if os(macOS)`, body no-op on iOS leg |
| `InterfaceSettingsViewTests.swift:12,29,37` | interface settings | per-`#if os` |
| `ViewRenderTests.swift:27`, `ExportChecklistsViewTests.swift:111`, `AboutViewTests.swift:23`, `MacWindowFrameTests.swift:1` | render/window | platform-gated |
| `CheckStitchUITests/` | one XCTest smoke | XCTest |

Fixtures/doubles: `CheckStitchTests/TestFixtures.swift` — `makeItem`,
`makeIsolatedDefaults`, `sharedTestEventStore` (a `@MainActor` global that must
outlive reminders to avoid SIGTRAP), `SpyReminderCreator`,
`SpyReminderDestination` (`:1-61`).

## Localization conventions

- Catalogs: `CheckStitch/Localizable.xcstrings` (App),
  `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings` (Core),
  `CheckStitchWatch/Localizable.xcstrings`, `CheckStitchWidget/Localizable.xcstrings`
  (`scripts/l10n-check.sh:13-18`).
- Six languages must be present: en, de, es, fr, ja, zh-Hans
  (`scripts/l10n-check.sh:10-11`).
- A new key needs: all 6 languages non-empty, non-English differing from
  English, and an entry in `LocalizationFixtures.requiredKeys`
  (`CheckStitchTests/LocalizationFixtures.swift:8-17`, App list `:18+`).
- Run `bash scripts/l10n-check.sh` first; the gate re-runs it.
- Resolve keys as resources, never eager `String(localized:)`
  (`CheckStitchWatch/WatchChecklistDetailView.swift:31`,
  `CheckStitch/PrivacySettingsContent.swift:29`). Tests use pinned-locale
  helpers `String.en` / `resolved(locale:)` (`LocalizationTestHelpers.swift:1-17`).
- Intent strings live in the App catalog (`RunChecklistIntent.swift:117`);
  `×%lld`-style labels are resolved at runtime because symbol generation cannot
  derive an identifier (`ChecklistDetailView.swift:426-431`).

## Build / verify gotchas

- New files under `CheckStitch/` need no `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`); `CheckStitchCore` is a sources-only
  SPM package.
- Simulator windows: the gate takes a host lock
  (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`), quits `Simulator.app`,
  pre-boots the worktree UDID headlessly, and shuts down only that UDID
  (see the `simulator` skill).
- Unit tests cannot stage SwiftUI bodies headlessly; they assert view *values*
  via `String(describing:)` (`ChecklistDetailViewTests.swift:1-19`).
- Sync/icon/render tickets cannot close on static evidence — verify the
  installed bundle (see `devicectl`).
- The core package's own warnings-as-errors is not separately enforced, but any
  Xcode leg is.