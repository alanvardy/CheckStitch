# Conventions & Ground Truth (CheckStitch)

Shared factual appendix for Design / Structure / Plan. Grounded in
`Makefile`, `scripts/`, repo `AGENTS.md`, and the research reports.

## Canonical commands

| Purpose | Command | Notes |
|---|---|---|
| Full gate | `./scripts/test.sh` | `make build` → sim pre-boot → `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`; prints `gate: ok`. Run before committing. |
| Simulator build | `make build` | scheme `CheckStitch` |
| Unit tests | `make test-unit` | `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`; fast inner loop |
| UI smoke | `make test-ui` | one `CheckStitchUITests` case, `build-for-testing` → `test-without-building` on this worktree's `.simulator_id` |
| All tests | `make test` | `test-unit` + `test-ui` |
| macOS compile leg | `make build-mac` | unsigned; platform check only, no signing/provisioning |
| Runnable macOS app | `make build-mac-signed` | dev team signing, embeds App Group + KVS entitlement |
| watchOS compile | `make watch-build` | watchOS simulator compile of `CheckStitchWatch`, unsigned |
| Widget build | `make widget-build` | widget target |
| Run on simulator | `make run` | builds then boots/installs/launches; requests its own window pinned to resolved UDID |
| Device deploy | `bash scripts/run-devices.sh` | real device + host Mac + paired Watch (`RUN_WATCH=0` skips watch) |
| Watch deploy | `bash scripts/run-watch.sh` | installs/launches on paired Apple Watch |
| Shell regression suite | `bash scripts/tests/run.sh` | also run by the gate; stubs `xcrun`/`defaults`/`make`/`open`/`osascript` on `PATH` (`scripts/tests/run.sh:1-55`) |
| Localization check | `bash scripts/l10n-check.sh` | static six-language + non-English-differs check; run before the full gate |
| Sim UDID resolve | `bash scripts/resolve-sim-udid.sh <dest>` | tested by `scripts/tests/run.sh` (`resolves_id_form_directly`, `resolves_name_form_from_simctl_list`) |

Warnings-as-errors: `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and
`GCC_TREAT_WARNINGS_AS_ERRORS=YES` in both Debug and Release project configs,
so every Xcode build fails on a compiler warning. `CheckStitchCore` (local SPM
package) is not separately enforced. `scripts/tests/run.sh`
(`warnings_as_errors_reaches_compiling_legs`) pins per-leg coverage.
`build-mac-signed`, `run-watch.sh`, `run-devices.sh` are outside the enforced set.

Destination precedence (`Makefile`): explicit `SIM=` > this worktree's
`.simulator_id` > shared default. Never leave a bare `name=` destination in a
script. The gate holds `${TMPDIR:-/tmp}/checkstitch-simulator.lock`, quits
`Simulator.app` once, pre-boots the resolved UDID headlessly, and releases the
lock after `make test` (repo AGENTS.md "Simulator windows").

## Test layout & conventions

- Unit target `CheckStitchTests/` is Swift Testing (macOS-hosted); imports
  `@testable import CheckStitchCore`. Suites are `struct <Thing>Tests` with
  `@Test`/`#expect`, behaviour-named functions, `@Test(arguments:)` for cases.
- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`;
  suites opt in with `@MainActor` (required for EventKit / view-model suites).
- Fakes/fixtures: `CheckStitchTests/TestFixtures.swift`, plus
  `BackgroundTestFixtures.swift`, `LocalizationTestHelpers.swift`,
  `StubBundle.swift`.
- `CheckStitchUITests/` holds exactly one XCTest smoke case.
- `#if os(...)`-gated suites (platform-specific, need care on the macOS leg):
  `AboutViewTests.swift`, `ChecklistDetailViewTests.swift`,
  `ColorCrossPlatformTests.swift`, `ExportChecklistsViewTests.swift`,
  `InterfaceSettingsViewTests.swift`, `MacWindowFrameTests.swift`,
  `PurchaseSettingsViewTests.swift`, `ViewRenderTests.swift`.
- `@MainActor` suites include most view/EventKit/store suites (e.g.
  `ChecklistRemindersTests`, `ChecklistRunViewModelTests`, `ChecklistStoreTests`,
  `ChecklistMergeTests`, `ChecklistSyncCoordinatorTests`, `RunChecklistIntentTests`,
  `WatchChecklistStoreTests`) — see `grep -l '@MainActor' CheckStitchTests/*.swift`.

### Suites most relevant to this ticket

| Suite | Covers |
|---|---|
| `ChecklistCodecTests.swift` | envelope encode/decode, versions, migration classification |
| `ChecklistStoreTests.swift` | CRUD, `setDestination`, import/duplicate, apply(remote) |
| `ChecklistMergeTests.swift` | LWW merge, tombstones, whole-checklist scalar copy |
| `ChecklistSyncServiceTests.swift`, `UbiquitousChecklistSyncTests.swift`, `ChecklistSyncingContractTests.swift` | push/pull, reconcile, transport contract |
| `ChecklistSyncCoordinatorTests.swift`, `ChecklistSyncMessageTests.swift` | watch coordinator de-dup and wire encoding |
| `ChecklistRemindersTests.swift` | run funnel: gate → permission → destination resolve → create |
| `EventKitReminderDestinationTests.swift`, `ReminderListsSnapshotTests.swift` | destination enumeration/resolve, missing detection |
| `ChecklistRunViewModelTests.swift` | run UI states; destination-missing short-circuit (`:64,74-77`) |
| `RunChecklistIntentTests.swift` | intent outcome/dialog messages (`~:127-130`) |
| `RunCounterTests.swift` | `RunGate` free-run limit/reserve/release |
| `CreateChecklistIntentTests.swift`, `ListChecklistsIntentTests.swift`, `ChecklistEntityQueryTests.swift` | other intents / entity query |
| `WidgetRunStateStoreTests.swift` | widget run-state record |
| `WatchChecklistStoreTests.swift` | watch pending-run lifecycle / run phases |
| `LocalizationTests.swift`, `LocalizedStringResolutionTests.swift`, `LocalizationFixtures.swift` | six-language enforcement, required keys, bundle embedding |
| `ChecklistExportTests.swift`, `ChecklistExportDocumentTests.swift`, `ChecklistShareTests.swift`, `SharedImportInboxTests.swift`, `ChecklistImportSessionTests.swift`, `ChecklistImportExportViewModelTests.swift` | export/import/share paths |
| `PurchaseServiceTests.swift` | entitlement used by `RunGate` |

Remaining suites cover appearance, settings, background, Sentry, language,
orientation, text size, About/privacy screens, and app metadata — not
destination/run related.

## Localization conventions

- Four catalogs: `CheckStitch/Localizable.xcstrings` (App),
  `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`
  (Core), `CheckStitchWatch/Localizable.xcstrings` (Watch),
  `CheckStitchWidget/Localizable.xcstrings` (Widget). `.lproj` holds only
  `InfoPlist.strings`.
- Six languages: `en, de, es, fr, ja, zh-Hans` (`scripts/l10n-check.sh`).
- A new user-facing key needs all six translations **and** an entry in
  `CheckStitchTests/LocalizationFixtures.swift` `requiredKeys` (guarded
  catalogs list at top of that file). Run `bash scripts/l10n-check.sh` first.
- Destination/run strings live at `CheckStitch/Localizable.xcstrings:1808`
  ("Create reminders from checklist") and `:5006` ("Couldn't create reminders
  for %@: %@"); resolved via `String(localized:..., table: "Localizable",
  bundle: .main)` (`RunChecklistIntent.swift:152`).

## Build / verify gotchas

- Run `make test-unit` for the fast check before `bash scripts/test.sh`.
- Never restore `SWIFT_DEFAULT_ACTOR_ISOLATION` to the test target; add
  `@MainActor` per suite instead.
- Sync/icon/render tickets cannot close on static evidence — verify the
  installed bundle on the target and state what the user should see.
- New files under `CheckStitch/` need no `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`).
- Destination is a bare `String?`; a stale/foreign identifier is preserved at
  rest and only fails at run time as `.destinationMissing`
  (`ChecklistStore.swift:269-273`), so model-level validation is not the guard.