# Conventions & Facts Appendix (VAR-1169)

Shared factual appendix for Design/Structure/Plan. Dense `file:line` refs.

## Canonical commands
- **Gate**: `./scripts/test.sh` — runs (in order): `make build` → worktree sim
  pre-boot → `make test` → `make build-mac` → `make watch-build` →
  `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`;
  prints `gate: ok`. `scripts/test.sh:1-132`.
- Simulator destination precedence (`Makefile:1-4`): explicit `SIM=` >
  this worktree's `.simulator_id` > shared `name=iPhone 17`. Gate holds a host
  lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock` (`scripts/test.sh:~50-90`).
- Fast unit-only: `make test-unit` → `xcodebuild … -destination platform=macOS
  CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` (`Makefile:91-99`).
  Use before the full gate.
- UI tests: `make test-ui` → `build-for-testing` then `test-without-building`,
  `-only-testing:CheckStitchUITests`, on `.simulator_id` (`Makefile:101-115`).
- Builds: `make build` (sim), `make build-mac` (unsigned macOS compile gate leg),
  `make build-mac-signed` (runnable, needs profile), `make watch-build`,
  `make widget-build`. `make test` = `test-unit` + `test-ui` (`Makefile:8-88`).
- Shell-test harness: `bash scripts/tests/run.sh` (stubs
  `xcrun`/`defaults`/`make`/`open`/`osascript` on PATH).
- App Store shots (not in gate): `make appstore-screenshots` /
  `bash scripts/appstore-screenshots.sh [class ...]`.
- Localization check: `scripts/l10n-check.sh` (new key → all 6 languages +
  `LocalizationFixtures.requiredKeys`).

## Warnings-as-errors
- `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` / `GCC_TREAT_WARNINGS_AS_ERRORS=YES` live
  in project-level Debug+Release of `CheckStitch.xcodeproj/project.pbxproj`, so
  every Xcode build fails on a warning. Core SPM is **not** separately enforced.
  `scripts/tests/run.sh` pins per-leg coverage (`warnings_as_errors_reaches_compiling_legs`);
  `build-mac-signed`, `run-watch.sh`, `run-devices.sh` are outside the enforced set.
- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`
  suites opt in with `@MainActor`.

## Layout / width seams (relevant to this ticket)
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidth.swift:9` public enum;
  `:10-12` `maxContentWidth = min(340, vw*0.6)`; `:17-19`
  `editFormMaxWidth = min(680, vw)`; both `nonisolated public static`.
- Call sites: `CheckStitch/ContentView.swift:495` (iOS header row), `:512` (card
  `LazyVStack`). Card padding `:523`; header padding `:496`; empty-state
  `:749`; rows `:580`; folder header `:667`. `emptyState` also at `:726-751`.
- Edit-form modifier `CheckStitch/ChecklistEditFormWidth.swift:12-15`; used at
  `ChecklistDetailView.swift:197`, `ChecklistOptionsView.swift:84`,
  `ItemEditView.swift:83`.
- Card plate constants `CheckStitch/CardPlate.swift:15` (radius 14),
  `:27` (`checklistTopMargin` 100), `:34` (`checklistRowHeight` 44). No padding
  constant.
- Orientation (app-target-only, never Core): `OrientationPreference.swift:14-40`
  (`allowsLandscape` key `:24`, default `true` `:27-29`), `OrientationPolicy`
  `:48-63` (mask ext `:58-66`); `AppDelegate.swift:38-52,55-60`;
  `AppearanceViewModel.swift:17-21`; ContentView binding `ContentView.swift:24`.
- **No** `UIDevice`, `horizontalSizeClass`, `@available`, or device-model reads
  anywhere in the four source roots.

## Test-suite inventory (`CheckStitchTests/`, all Swift Testing unless noted)
Pure-core (plain `struct`, no `@MainActor`, `@testable import CheckStitchCore`):
- `ChecklistWidthTests.swift` — pins `maxContentWidth`/`editFormMaxWidth` (`:8,13,18,25,32`).
- `ScalingTests.swift` — number clamping `1...99` via `@Test(arguments:)` (`:5`).
- `ChecklistItemTests.swift`, `ChecklistItemDateTests.swift`,
  `ChecklistGroupingTests.swift`, `ChecklistMergeTests.swift`,
  `ChecklistCodecTests.swift`, `RunCounterTests.swift`,
  `ChecklistRemindersTests.swift`, `CardPlateTests.swift` (layout constants,
  `:30`), `AppearanceModeTests.swift`, `AppLanguagePreferenceTests.swift`,
  `AppLanguageTests.swift`, `AppInfoTests.swift`, `AppGroupTests.swift`,
  `CrashReportingPreferenceTests.swift`, `SentryConfigurationTests.swift`,
  `SentryScrubberTests.swift`, `ScalingTests.swift`, `HarnessTests.swift`,
  `LaunchSeamsTests.swift`, `ReminderListsSnapshotTests.swift`,
  `ChecklistSyncMessageTests.swift`, `ChecklistWidgetDisplayModelTests.swift`,
  `WatchChecklistStoreTests.swift`, `WidgetRunStateStoreTests.swift`,
  `CreateChecklistIntentTests.swift`, `ListChecklistsIntentTests.swift`,
  `RunChecklistIntentTests.swift`, `ChecklistExportTests.swift`,
  `ChecklistExportDocumentTests.swift`, `ChecklistImportSessionTests.swift`,
  `SharedImportInboxTests.swift`, `UbiquitousChecklistSyncTests.swift`,
  `EventKitReminderCreatorTests.swift`, `EventKitReminderDestinationTests.swift`,
  `ChecklistCreatorTests.swift`, `ChecklistEntityQueryTests.swift`,
  `ChecklistStoreTests.swift`, `ChecklistShareTests.swift`,
  `ChecklistSyncDiagnosticsTests.swift`, `ChecklistSyncingContractTests.swift`,
  `ChecklistSyncServiceTests.swift`, `ChecklistSyncCoordinatorTests.swift`,
  `SettingsBindingsTests.swift` (`@Suite(.serialized)`), `AppEnvironmentTests.swift`.
`@MainActor` suites (view model / EventKit / render):
- `ViewRenderTests.swift` (`ImageRenderer` oracle `:18-30`),
  `ChecklistDetailViewTests.swift` (`:13`), `ChecklistOptionsViewTests.swift`
  (`:9`), `ExportChecklistsViewTests.swift` (`:10`),
  `ChecklistListViewModelTests.swift` (`:6`), `ChecklistRunViewModelTests.swift`,
  `ChecklistImportExportViewModelTests.swift`, `SettingsViewModelTests.swift`,
  `SettingsDataActionQueueTests.swift`, `PurchaseSettingsViewTests.swift`,
  `PurchaseServiceTests.swift`, `AboutViewTests.swift`,
  `InterfaceSettingsViewTests.swift`, `PrivacySettingsContentTests.swift`,
  `ContentViewSettingsActionTests.swift`, `PromptScalingSheetTests.swift`,
  `TextSizeTests.swift` (`:7`), `OrientationPreferenceTests.swift` (`:7`),
  `BackgroundImageStoreTests.swift` (`@Suite(.serialized)`),
  `BackgroundPhotoLayerTests.swift`, `BackgroundFadeTests.swift`,
  `BackgroundViewModelTests.swift`, `AppearanceModePreferenceTests.swift`,
  `AppLanguageSyncTests.swift`, `LocalizationTests.swift`,
  `LocalizedStringResolutionTests.swift`, `SmokeTests.swift`,
  `ColorCrossPlatformTests.swift`, `MacWindowFrameTests.swift`.
Platform gating in tests:
- Whole-file `#if os(macOS)`: `MacWindowFrameTests.swift:1-63`,
  `ColorCrossPlatformTests.swift:5`.
- Per-case `#if os(iOS)/#else`: `InterfaceSettingsViewTests.swift:12-19,29-39`;
  `CheckStitchUITests/CheckStitchUITests.swift:31-34`.
- `#if os(macOS) … nsImage #else … uiImage` inline: `ChecklistDetailViewTests.swift:72,165,181,213,283,305,321,356`.
- Shared fixtures: `TestFixtures.swift`, `BackgroundTestFixtures.swift`,
  `LocalizationFixtures.swift`, `LocalizationTestHelpers.swift`,
  `StubBundle.swift`.
`CheckStitchUITests/CheckStitchUITests.swift` — one XCTest launch/accessibility
smoke + UI-testing seam cases (not Swift Testing).

## Build/verify gotchas
- Test targets don't inherit `SWIFT_DEFAULT_ACTOR_ISOLATION`; never restore the
  app's default there — suites opt in with `@MainActor`.
- UI tests must use `.simulator_id`; never a bare `name=` destination (shared
  device wedges parallel agents). Device lookup by name is the App-Store-shots
  exception and always resolves to a UDID first.
- Sync/icon/render tickets can't close on static evidence — verify on the
  installed bundle and state what the user should see.
- New files under `CheckStitch/` need no `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`).
- `scripts/*.sh` are `#!/bin/bash` + `set -euo pipefail`, mode `100755`.
