# Conventions — shared factual appendix

Repo root: `/Users/vardy/dev/CheckStitch`.

## Build / test / lint / verify commands

- **Gate** (full): `./scripts/test.sh` — the single authoritative gate.
- `make build` — simulator build, scheme `CheckStitch` (gate leg 1).
- `make build-mac` — unsigned macOS compile leg (gate's platform check; `CODE_SIGNING_ALLOWED=NO`).
- `make build-mac-signed` — signed, runnable macOS app (`-allowProvisioningUpdates`, team-signs so `AppGroup.entitlements` incl. KVS id is embedded). Outside warnings-as-errors enforcement.
- `make run` — build then boot/install/launch on simulator.
- `make watch-build` — watchOS simulator compile of `CheckStitchWatch` (same `CheckStitchCore`, unsigned, sim-free).
- `make test` = `make test-unit` + `make test-ui`.
- `make test-unit` — `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, warnings-as-errors.
- `make test-ui` — exactly one `CheckStitchUITests` smoke via `build-for-testing` + `test-without-building` on `$(SIM)`.
- `bash scripts/run-watch.sh` — build `CheckStitchWatch`, install + launch on paired watch (devicectl, name→identifier).
- `bash scripts/run-devices.sh` — install + launch on real device / host Mac / watch; honours `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA`; `RUN_WATCH=0` skips watch.
- `bash scripts/tests/run.sh` — shell tests (also run by gate); stubs `xcrun`/`defaults`/`make`/`open`/`osascript`.
- `scripts/l10n-check.sh` — localization key check; run **before** adding a user-facing string.
- `shellcheck scripts/*.sh scripts/tests/*.sh` — gate-lint; scripts must parse under `/bin/bash` 3.2.

## Warnings-as-errors enforcement

- `WARNINGS_AS_ERRORS := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES` (`Makefile:20`) must reach every compiling Swift gate leg; a compiler warning fails the gate.
- Pinned legs: `scripts/tests/run.sh:395` `WARNINGS_AS_ERRORS_LEGS=(build-mac build test-unit test-ui watch-build)`; `:398-416` asserts each logs both flags; `:421-429` detects a stripped flag.
- `run.sh:369-385` asserts every `ENABLE_APP_SANDBOX=YES` buildSettings block also has `ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES`.
- Device helper legs (`build-mac-signed`, `run-watch.sh`, `run-devices.sh`) are intentionally outside enforcement.

## Test-suite inventory

| Path | Covers | Platform / gating |
|---|---|---|
| `CheckStitchTests/ChecklistCreatorTests.swift` | Core checklist creation model | Swift Testing, macOS |
| `CheckStitchTests/ChecklistRunViewModelTests.swift` | run view-model flow | `@MainActor` |
| `CheckStitchTests/ChecklistStoreTests.swift` | store loads/mutators/saves | macOS |
| `CheckStitchTests/ChecklistCodecTests.swift` | encode/decode/classify/migrations | macOS |
| `CheckStitchTests/EventKitReminderCreatorTests.swift` | legacy EventKit creator | `@MainActor` |
| `CheckStitchTests/EventKitReminderDestinationTests.swift` | destination seam | `@MainActor` |
| `CheckStitchTests/ChecklistRemindersTests.swift` | orchestration + run gate | macOS |
| `CheckStitchTests/RunChecklistIntentTests.swift` | Siri intent perform (incl. ghost-id) | `@MainActor`, injected seams |
| `CheckStitchTests/ListChecklistsIntentTests.swift` | list intent | `@MainActor` |
| `CheckStitchTests/ChecklistEntityQueryTests.swift` | entity query | `@MainActor` |
| `CheckStitchTests/ContentViewSettingsActionTests.swift` | settings action | macOS |
| `CheckStitchTests/WatchChecklistStoreTests.swift` | watch KVS store | macOS |
| `CheckStitchTests/AppGroupTests.swift` | entitlement suite-name pinning | macOS |
| `CheckStitchTests/LocalizationFixtures.swift` | `requiredKeys` for new string keys | shared fixture |
| `CheckStitchUITests/CheckStitchUITests.swift` | one XCTest smoke | simulator, XCTest |

Notes:
- Unit suites use Swift Testing (`@Test`, `#expect`, behaviour-named functions). `@MainActor` on any suite touching EventKit or a view model.
- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with `@MainActor`. Never restore the app default in test targets.
- Fakes live in `CheckStitchTests/TestFixtures.swift` (incl. `SpyReminderDestination`).

## Gotchas surfaced by research

- **Destination precedence** (`Makefile:1-19`): explicit `SIM=` > this worktree's `.simulator_id` > `name=iPhone 17` fallback. Never a bare `name=` destination in a script — it selects a shared device and wedges parallel agents.
- **Simulator lock** (`scripts/test.sh:32-…`): bounded host lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock`; single EXIT trap releases it and shuts down only the gate's resolved UDID (never `all`/`booted`). `LOCK_TIMEOUT` default 60; on timeout the gate warns and runs unlocked.
- **New Swift files need no pbxproj edit** (`PBXFileSystemSynchronizedRootGroup`, `pbxproj:62-86`). A new **target** does need a `PBXNativeTarget` + committed shared scheme + Makefile leg + gate leg.
- **App Group / KVS**: `AppGroup.defaults = UserDefaults(suiteName:"group.app.alanvardy.CheckStitch") ?? .standard` (`CheckStitch/AppGroup.swift:6-11`); pinned byte-for-byte in `CheckStitch/AppGroup.entitlements`. Only signed slices embed entitlements (so only signed builds sync KV through iCloud). KVS ubiquity entitlement `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)app.alanvardy.CheckStitch`.
- **Fresh store per caller** is the established pattern for out-of-app callers: `ChecklistStore(defaults: AppGroup.defaults)` (`RunChecklistIntent.swift:42`, `ChecklistEntity.swift:28-31`). No singleton store exists.
- **Cold-process no-prompt rule**: a non-app process must not prompt for EventKit permission (`RunChecklistIntent.swift:53-54`); do a status-only `accessStatus()` pre-check.
- **Store ownership**: app's single store is created in `MyApp.init()` and injected; sync (`ChecklistSyncService`) is started there too.
- **User-facing strings**: new keys need all 6 languages in `CheckStitch/Localizable.xcstrings` (and `CheckStitchWatch/Localizable.xcstrings` for watch) + a `LocalizationFixtures.requiredKeys` entry; run `scripts/l10n-check.sh` first. `.lproj/` holds only `InfoPlist.strings`.

## Signing values (working, do not re-derive)

- `DEVELOPMENT_TEAM = 6NWX2DHB9Q`
- Bundle id `app.alanvardy.CheckStitch` (watch: `app.alanvardy.CheckStitch.watchkitapp`)
- App Group `group.app.alanvardy.CheckStitch`
- macOS slice signs with same team; `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"`.
- On a machine without the profile, add `-allowProvisioningUpdates`.