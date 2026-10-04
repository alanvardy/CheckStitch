# Conventions — shared factual appendix for Design, Structure, and Plan

Build/verify/lint/test facts for the CheckStitch repo (worktree branch
`alanvardy-var-809-scaling-templates`). Paths relative to repo root.

## Canonical commands

- **Gate** (final, runs once): `./scripts/test.sh` → `make build` (simulator) →
  headless pre-boot of this worktree's `.simulator_id` UDID → `make test` →
  `make build-mac` → `make watch-build` → `scripts/tests/run.sh` →
  `shellcheck scripts/*.sh scripts/tests/*.sh`, prints `gate: ok`.
- **Fast unit loop**: `make test-unit` before the full gate. Runs `CheckStitchTests`
  on `platform=macOS` with `CODE_SIGNING_ALLOWED=NO` (no sim, no signing).
- **Builds**: `make build` (iOS simulator, scheme `CheckStitch`); `make build-mac`
  (unsigned macOS compile leg — the gate's platform check, provisioning-free);
  `make build-mac-signed` (runnable macOS app, team-signed); `make run` (build+boot+
  install+launch on a simulator); `make watch-build` (watchOS simulator compile of
  `CheckStitchWatch`, unsigned); `make widget-build` (widget iOS compile).
- **UI smoke**: `make test-ui` — exactly one `CheckStitchUITests` case via
  `build-for-testing` → `test-without-building` on this worktree's `.simulator_id`
  simulator. Never a bare `name=` destination.
- **Localization**: `scripts/l10n-check.sh` first (see localization skill); new key
  needs all 6 languages in its catalog + a `LocalizationFixtures.requiredKeys` entry.
- Destination precedence (Makefile:3-5): explicit `SIM=` > worktree `.simulator_id` >
  shared default. `tests.sh` and `test-ui` are pinned to the worktree UDID.
- Warnings-as-errors: `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` /
  `GCC_TREAT_WARNINGS_AS_ERRORS=YES` in project-level Debug+Release configs
  (Makefile:19-23), enforced on every build. The `CheckStitchCore` local SPM package
  is NOT separately enforced. `scripts/tests/run.sh` pins coverage
  (`warnings_as_errors_reaches_compiling_legs`).

## Test-suite inventory (CheckStitchTests, macOS-hosted Swift Testing unless noted)

- **Data model / codec / merge**:
  - `ChecklistEntityQueryTests.swift`, `ChecklistItemTests.swift`,
    `ChecklistItemDateTests.swift` (per-field clocks / date), `ChecklistItemPriorityTests.swift`.
  - `ChecklistCodecTests.swift` — codec round-trip, defaults, versioning (VAR-969
    store/codec XCTest suites also live here per AGENTS.md).
  - `ChecklistMergeTests.swift` — LWW reconciliation, tombstones, per-field wins.
  - `ChecklistStoreTests.swift` — duplicate / importInsert / importReplace / rename /
    set* no-op-guard behaviour.
  - `ChecklistGroupingTests.swift`, `ChecklistSyncingContractTests.swift`,
    `UbiquitousChecklistSyncTests.swift`, `ChecklistSyncCoordinatorTests.swift`,
    `ChecklistSyncDiagnosticsTests.swift`, `ChecklistSyncMessageTests.swift`.
- **Run path**:
  - `ChecklistCreatorTests.swift` — Path B (`ChecklistCreator.create`, numbering, blank-drop).
  - `ChecklistRemindersTests.swift` — Path A (`ChecklistReminders.create`), gate wiring (:21-23, 391-486).
  - `EventKitReminderCreatorTests.swift`, `EventKitReminderDestinationTests.swift`,
    `ReminderListsSnapshotTests.swift`, `ChecklistRunViewModelTests.swift`,
    `RunCounterTests.swift`.
- **Intent**: `RunChecklistIntentTests.swift` (error/validation at :65-68),
  `ListChecklistsIntentTests.swift`.
- **Import/export/share**: `ChecklistExportTests.swift`, `ChecklistExportDocumentTests.swift`,
  `ChecklistImportExportViewModelTests.swift`, `ChecklistImportSessionTests.swift`
  (gate at :241-243), `ChecklistShareTests.swift`, `SharedImportInboxTests.swift`,
  `ChecklistImportSessionTests`.
- **UI/view (thin-screen render, cross-platform)**: `ChecklistDetailViewTests.swift`,
  `ChecklistRunViewModelTests.swift`, `ViewRenderTests.swift`, `CardPlateTests.swift`,
  `SmokeTests.swift`, plus settings/background/orientation/text-size suites.
- **Widget/watch**: `ChecklistWidgetDisplayModelTests.swift`,
  `WatchChecklistStoreTests.swift`, `WidgetRunStateStoreTests.swift`.
- **Localization**: `LocalizationTests.swift`, `LocalizedStringResolutionTests.swift`,
  `LocalizationFixtures.swift` (requiredKeys + guardedCatalogs), `LocalizationTestHelpers.swift`.
- Fixtures in `TestFixtures.swift`, `BackgroundTestFixtures.swift`, `StubBundle.swift`.
- `CheckStitchUITests/` — one XCTest smoke (UI, not Swift Testing).
- Unit suites import `@testable import CheckStitchCore`. Test targets deliberately do
  NOT set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in per-suite with `@MainActor`
  (required for anything touching EventKit or a view model). Never restore the app's
  default isolation in tests.

## Build / verify gotchas surfaced by research

- New user-facing strings go in the catalog that owns the surface: the detail screen /
  UI copy → `CheckStitch/Localizable.xcstrings` (App); intent run-time messages →
  `CheckStitchCore/.../Resources/Localizable.xcstrings` (Core, `LocalizedStringResource`
  resolved via `.resolvedInAppLanguage()`); watch/widget have their own catalogs. Each
  catalog key needs en/fr/es/de/ja/zh-Hans. `.lproj` holds only `InfoPlist.strings`.
- `make test-ui` depends on `.simulator_id`; the gate pre-boots it headlessly. Never run
  two simulator-touching processes on the shared default device (wedges parallel agents).
- Compiler is the oracle for SwiftUI SDK questions (`make build` / `make test-unit`).
- New `CheckStitch/` app-target files need no `project.pbxproj` edit (used
  `PBXFileSystemSynchronizedRootGroup`); the Core SPM package auto-includes new files
  under `CheckStitchCore/Sources/`.
- `scripts/*.sh` are `#!/bin/bash` with `set -euo pipefail`, mode 100755; keep the
  plural `run-devices.sh` name.
- Codec additive fields decode to defaults with no `ChecklistCodec.currentVersion` bump
  (currently 5). Only structural/migration changes bump the version.