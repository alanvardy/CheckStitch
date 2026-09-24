# Conventions

Shared factual appendix for Design/Structure/Plan. Do not re-open source to
recover any of this.

## Build / test / verify commands

- **Gate:** `bash ./scripts/test.sh` — the authoritative gate; prints `gate: ok`.
- **Fast unit verify:** `make test-unit` (macOS host, `CODE_SIGNING_ALLOWED=NO`,
  `-only-testing:CheckStitchTests test`; Makefile:71-83) then full gate.
- **UI smoke:** `make test-ui` — `build-for-testing` → `-only-testing:CheckStitchUITests
  test-without-building` on this worktree's `.simulator_id` (`$(SIM)`, never a bare `name=`
  destination; Makefile:85-103).
- `make build` (simulator), `make build-mac` (unsigned macOS compile leg),
  `make build-mac-signed` (runnable macOS), `make watch-build` (watchOS sim compile).
- Every Swift leg compiles with `WARNINGS_AS_ERRORS` (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`,
  `GCC_TREAT_WARNINGS_AS_ERRORS=YES`) — a compiler warning fails the gate.
- `scripts/tests/run.sh` runs stub-based shell regressions (stubs `xcrun`/`defaults`/`make`/
  `open`/`osascript`; `new_stubs` at 8-31, `run_case` tallies).

## Test-suite inventory (`CheckStitchTests/`, macOS-hosted Swift Testing)

Imports: `@testable import CheckStitchCore` and/or `@testable import CheckStitch`
(~50 files use `@testable`; 18 import Core). Test targets deliberately do NOT set
`SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in per-suite with `@MainActor struct ...` or on
fixtures/doubles (`TestFixtures.swift:21,26,39`).

Entity/model suites: `ChecklistItemTests`, `ChecklistItemDateTests`, `ChecklistMergeTests`,
`ChecklistShareTests`, `ChecklistWidthTests`, `AppearanceModeTests`, `AppearanceModePreferenceTests`,
`AppLanguageTests`, `AppLanguagePreferenceTests`, `AppInfoTests`, `OrientationPreferenceTests`,
`TextSizeTests`, `RunCounterTests`, `LocalizedStringResolutionTests`, `ChecklistEntityQueryTests`.

Store suites: `ChecklistStoreTests`, `BackgroundImageStoreTests`, `WatchChecklistStoreTests`,
`SettingsDataActionQueueTests`, `SharedImportInboxTests`.

View-model suites: `ChecklistRunViewModelTests`, `ChecklistListViewModelTests`,
`ChecklistImportExportViewModelTests`, `SettingsViewModelTests`, `BackgroundViewModelTests`,
`ChecklistImportSessionTests`.

Sync/codec suites: `ChecklistCodecTests`, `ChecklistSyncCoordinatorTests`, `ChecklistSyncMessageTests`,
`ChecklistSyncServiceTests`, `UbiquitousChecklistSyncTests`, `ChecklistRemindersTests`,
`ReminderListsSnapshotTests`, `ChecklistCreatorTests`.

EventKit seam suites: `EventKitReminderCreatorTests`, `EventKitReminderDestinationTests`.

View/SwiftUI render suites: `AboutViewTests`, `BackgroundFadeTests`, `CardPlateTests`,
`ChecklistDetailViewTests`, `ExportChecklistsViewTests`, `InterfaceSettingsViewTests`,
`PurchaseSettingsViewTests`, `PrivacySettingsContentTests`, `MacWindowFrameTests`,
`ViewRenderTests`, `SmokeTests`, `BackgroundPhotoLayerTests`, `ChecklistWidthTests`,
`ListChecklistsIntentTests`, `RunChecklistIntentTests`.

Localization: `LocalizationTests`, `AppLanguageSyncTests`, `LocalizedStringResolutionTests`.

Shared fixtures: `TestFixtures.swift` (`makeItem:7`, `makeIsolatedDefaults:12-17`,
`sharedTestEventStore:18`, `SpyReminderCreator:22-47`, `SpyReminderDestination:50-113`),
`StubBundle.swift:7-13` (`@unchecked Sendable` required),
`BackgroundTestFixtures.swift` (`jpegData` 1×1 JPEG 6-16), `LocalizationFixtures.swift`
(`guardedCatalogs=["App","Core","Watch"]`, `requiredKeys`), `LocalizationTestHelpers.swift`,
`HarnessTests.swift` (exercises fixtures).

UI smoke (XCTest, not Swift Testing): `CheckStitchUITests/CheckStitchUITests.swift` — one
`testLaunchAndAccessibilitySmoke`, `runsForEachTargetApplicationUIConfiguration=false`,
`continueAfterFailure=false`.

## Style rules a new suite must follow

- `struct <Thing>Tests`; Swift Testing `@Test`/`#expect`; behaviour-named functions (never
  `test`-prefixed); `@Test(arguments:)` for data-driven cases; `@MainActor` on any suite
  touching EventKit or a view model; fakes live in `TestFixtures.swift`; private helpers as
  `private func`.
- Core logic must be pure/DI-friendly: use `makeIsolatedDefaults()`, injected `now`,
  `textEditDelay: nil` for synchronous saves, injected side-effect seams
  (`SpyReminderDestination`, `SpyPurchaseProvider`, `InMemoryChecklistSync`,
  `FakeChecklistSyncTransport`), temp dirs for `BackgroundImageStore`.

## Gotchas

- Headless `body` fatal-error: reading `body`/`.environment().body` without a live scene
  fatal-errors (`ChecklistDetailViewTests.swift:1-14`); assert via `String(describing:)` on
  state-slot names/environment seams plus offscreen `ImageRenderer` render-oracles
  (`nsImage`/`uiImage`, `ViewRenderTests.swift:1-22`).
- `StubBundle` subclass must restate `@unchecked Sendable` or Swift 6 + warnings-as-errors rejects it.
- `sharedTestEventStore` must be process-lifetime (weak `EKReminder` ref to the store).
- Destinations: use this worktree's `.simulator_id` for the UI leg; never a bare `name=`
  destination (selects a shared device).
- New user-facing strings belong in `Localizable.xcstrings` (all 6 languages) +
  `LocalizationFixtures.requiredKeys`; run `scripts/l10n-check.sh`.
- Repo gate has no custom CI build-test workflow beyond dependabot/actionlint yamls.