# Conventions (shared factual appendix)

Canonical commands, test-suite inventory, and build/verify gotchas for the
CheckStitch repo. Structure and Plan should rely on this instead of reopening
`Makefile`/`scripts/`.

## Canonical commands
- **Gate**: `./scripts/test.sh` — `make build` (simulator) → headless pre-boot
  of this worktree's `.simulator_id` → `make test` → `make build-mac` →
  `make watch-build` → `scripts/tests/run.sh` → `shellcheck scripts/*.sh`,
  prints `gate: ok`. Takes a bounded host simulator lock
  (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`, default `LOCK_TIMEOUT=60`).
- **Fast unit loop**: `make test-unit` — runs `CheckStitchTests` on
  `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`.
- **UI smoke**: `make test-ui` — one `CheckStitchUITests` case via
  build-for-testing → test-without-building on the worktree `.simulator_id`.
- **Build/compile**: `make build` (simulator), `make build-mac` (unsigned
  macOS compile leg), `make watch-build` (watchOS compile of `CheckStitchWatch`,
  sim-free).
- **Devices**: `bash scripts/run-devices.sh` (real device + host + watch,
  `RUN_WATCH=0` to skip watch leg); `bash scripts/run-watch.sh` resolves the
  watch by name to an identifier — never a bare name in a destination.
- **Localization**: `scripts/l10n-check.sh` (fast shell/Python mirror of the
  Swift `LocalizationTests`).

## Warnings-as-errors
Every gate leg that compiles Swift passes the shared `WARNINGS_AS_ERRORS`
Makefile variable (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`,
`GCC_TREAT_WARNINGS_AS_ERRORS=YES`), so a compiler warning fails the gate.
`scripts/tests/run.sh` pins the flag per compiling leg; `build-mac-signed`,
`run-watch.sh`, `run-devices.sh` are outside enforcement.

## Test-suite inventory (`CheckStitchTests/`, Swift Testing, macOS-hosted)
- `ChecklistCodecTests.swift` (`@MainActor :5`) — envelope/version/classify
  outcomes, absent-key decode defaults, round trips; `PinnedV4Codec`/`PinnedV5Codec`
  pin the v4/v5 `classify` switches.
- `ChecklistStoreTests.swift` (`@MainActor :5`) — store mutations incl.
  `setPrefixesReminderNumbers` suite (`:1840-1882`), version migration, imports.
- `ChecklistMergeTests.swift` (`@MainActor :6`) — newest-editor-wins merge.
- `ChecklistImportSessionTests.swift` / `ChecklistImportExportViewModelTests.swift`
  (`@MainActor`) — import stage/commit, future-version rejects.
- `ChecklistSyncServiceTests.swift` (`@MainActor :6`) — v1 legacy, version-4
  field-clock seeding.
- `WatchChecklistStoreTests.swift` (`@MainActor :5`) — watch store decode paths.
- `ChecklistDetailViewTests.swift` (`@MainActor :13`, `#if os(macOS)` ×4) —
  the edit-checklist view tests (numbering toggle assertions expected to extend
  to a new toggle).
- View/reference suites: `InterfaceSettingsViewTests.swift:12/29/37`,
  `ExportChecklistsViewTests.swift:28,36`, `ContentViewSettingsActionTests`,
  `AboutViewTests.swift:23`, `PurchaseSettingsViewTests.swift:66`,
  `BackgroundImageStoreTests`, `OrientationPreferenceTests`.
- Localization: `LocalizationTests.swift`, `LocalizationTestHelpers.swift`
  (6 langs `["en","de","es","fr","ja","zh-Hans"]` at `:67`),
  `LocalizationFixtures.swift`.
- `CheckStitchUITests/CheckStitchUITests.swift` — one XCTest smoke,
  `#if os(iOS)` (`:34`). macOS test phase still compiles the bundle.

## Platform gating / actor isolation
- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`;
  suites opt in with `@MainActor` (near-universal for codec/sync/store/view-model
  suites). Never restore the app's default there.
- `#if os(...)`: whole-file (`MacWindowFrameTests.swift:1`,
  `ColorCrossPlatformTests.swift:5`) or per-region inside otherwise shared files.

## Signing
`DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App
Group `group.app.alanvardy.CheckStitch`; add `-allowProvisioningUpdates` when no
profile. macOS slice signs with the same team; `make build-mac` is the
provisioning-free gate leg.

## Localization fixture gotcha
A new user-facing key joins **one** catalog (`App`/`Core`/`Watch`) with all six
languages, **and** is added to `LocalizationFixtures.requiredKeys`
(`LocalizationFixtures.swift:12`, grouped alphabetically per catalog) or the
Swift `everyRequiredKeyIsPresent`/`catalogsHaveAllSixLanguages` checks and the
shell `l10n-check.sh` fail. `nonEnglishValuesDifferFromEnglish` must hold unless
the `(catalog, key)` is listed in `excludedIdentities` (`:166-183`).

## Editing files
`edit` takes one top-level `path` per call with an `edits` array; `oldText` must
be byte-exact (copy from a prior `read`). JSON/`.xcstrings` blocks are the usual
miss — prefer small unique anchors. A rejected call applies nothing.
