# Conventions

Repo root: `/Users/vardy/dev/alanvardy-var-1033-set-language` (slice of
`/Users/vardy/dev/CheckStitch`). Swift/SwiftUI iOS app + core Swift package +
watch target + unit/UI test targets.

## Canonical commands

From `Makefile` (targets at `Makefile:17-88`):

- `make build` — simulator build (`xcodebuild`, scheme `CheckStitch`) — `Makefile:17`
- `make build-mac` — unsigned macOS compile leg (gate's platform check; no signing, no provisioning) — `Makefile:30`
- `make build-mac-signed` — runnable macOS app signed with dev team (`6NWX2DHB9Q`, `-allowProvisioningUpdates`) so `AppGroup.entitlements` incl. KVS identifier is embedded; used by `run-devices.sh` — `Makefile:40`
- `make run` → build then boot/install/launch on a simulator (window pinned to resolved UDID) — `Makefile:57`
- `make watch-build` — watchOS simulator compile of `CheckStitchWatch` (same `CheckStitchCore` package, unsigned, sim-free) — `Makefile:50`
- `make test` = `test-unit` + `test-ui` — `Makefile:60`
- `make test-unit` — `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO` (no sim, no signing) — `Makefile:64`
- `make test-ui` — exactly one `CheckStitchUITests` smoke case via `build-for-testing` → `test-without-building` on this worktree's `.simulator_id` — `Makefile:75`
- `make clean` — `Makefile:88`

Scripts (`bash`, `set -euo pipefail`, committed `100755`):

- `scripts/test.sh` — **the gate**: `make build` → headless pre-boot of this worktree's simulator → `make test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh` → prints `gate: ok` (`scripts/test.sh:33,98,104,108,114-117,121`)
- `bash scripts/run-watch.sh` — build + install + launch `CheckStitchWatch` on the paired Apple Watch via `devicectl` (resolve by name to identifier; never a bare name in a destination)
- `bash scripts/run-devices.sh` — install + launch on a real device (Developer Mode; prefers iPhone); honours `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA` overrides. Kept plural — the `r` fish alias runs it
- `scripts/run-simulator.sh`, `scripts/resolve-sim-udid.sh` — simulator boot/UDID resolve helpers
- `scripts/tests/run.sh` — shell tests; stubs `xcrun`/`defaults`/`make`/`open`/`osascript` on `PATH`
- `bashrun`/`xsh` fish helpers for temp bash scripts; never heredocs in fish

Simulator protocol: gate holds bound host lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock`, quits `Simulator.app` once, pre-boots this worktree's `.simulator_id` UDID headlessly between `make build` and `make test`, releases on EXIT trap. Missing `.simulator_id` → skip; unresolvable → hard error; shutdown scoped to resolved UDID, never `all`/`booted`. `LOCK_TIMEOUT` (default 60) bounds the wait; on timeout the gate warns and runs without the lock. Destination precedence: explicit `SIM=` > worktree `.simulator_id` > shared default (see `Makefile`); never a bare `name=` destination.

## Test suite inventory

Unit tests are Swift Testing (`@Test`, `#expect`, behaviour-named functions,
`@Test(arguments:)` for cases) in `CheckStitchTests/`; XCTest reserved for the
one `CheckStitchUITests` smoke. Test targets deliberately do **not** set
`SWIFT_DEFAULT_ACTOR_ISOLATION`, so suites opt in with `@MainActor` where
needed. Imports: `@testable import CheckStitchCore`.

| File | Covers | Notes |
|---|---|---|
| `CheckStitchTests/LocalizationTests.swift` | All three `Localizable.xcstrings` catalogs: parse, six languages non-empty, required keys, watch superset, canary non-English values differ, compiled `de.lproj` embedding (core + main), unknown-key fallback, `InfoPlist.strings` per language, malformed catalog, missing bundle | Swift Testing; hosted in app so `Bundle.main` = app bundle; run in unit target (also compiled/run in the macOS test phase per `CheckStitchUITests.swift:31-33`) |
| `CheckStitchTests/LocalizationTestHelpers.swift` | `String.en` locale pin, `Bundle.core`/`Bundle.main` resolution, xcstrings JSON loader `Catalogs.all` | Helpers, no tests |
| `CheckStitchTests/LocalizationFixtures.swift` | `guardedCatalogs`, `requiredKeys` (App ~70 / Core 5 / Watch 5), `infoPlistTargets`, `excludedIdentities` | Fixture data |
| `CheckStitchTests/AppearanceModeTests.swift` | raw-value rewrites + `AppearanceMode.load`, core-catalog titles, `makeIsolatedDefaults()` | Pref persistence path |
| `CheckStitchTests/AppearanceModePreferenceTests.swift` | set→read round-trip, unknown stored value → fallback | Pref persistence path |
| `CheckStitchTests/SettingsBindingsTests.swift` | staging never writes defaults; snapshot reads current; `ContentView.writeBack` persists each key; `UserDefaults.standard.removeObject` cleanup | Uses `makeIsolatedDefaults()` |
| `CheckStitchTests/ViewRenderTests.swift` | SettingsView renders all appearance modes (`settingsViewListsAllAppearanceModes`, systemImage non-empty); render views use `.constant(.system)` bindings | UI-shape pinning |
| `CheckStitchTests/TestFixtures.swift` | `makeIsolatedDefaults()` shared isolated-UserDefaults helper | Shared fixture |
| `CheckStitchUITests/CheckStitchUITests.swift` | One XCTest smoke: launch + accessibility audit, no localization assertions | macOS-hosted ui-testing |

## Build/verify gotchas

- **Gate is `./scripts/test.sh`** — never declare work done while it fails; `make test-unit` is the fast pre-check.
- **Locale pinning does not switch language in tests**: hosted runner resolves `String(localized:)` with the process (English) locale; `locale:` pins only make output deterministic English. Verifying non-English rendered strings requires the compiled-table diff technique, not `String(localized:locale:)` (empirically confirmed in VAR-986 plan, `.pi/orksorksorks/alanvardy-var-986-add-localizations/implement.md:31`).
- **Catalog discipline is enforced by tests**: every key non-empty in all six languages in all three catalogs + canary that non-English values differ from English (minus `excludedIdentities`). New UI strings must be added to the right catalog with translations, or the localization suites fail.
- **`InfoPlist.strings`**: `GENERATE_INFOPLIST_FILE = YES`; App needs `NSRemindersFullAccessUsageDescription` + `NSRemindersUsageDescription` + `CFBundleDisplayName` per language; Watch needs only `CFBundleDisplayName` (never touches EventKit slides). Reference: `/Users/vardy/dev/SingleThread`.
- **Platform**: iOS Simulator vs macOS slice vs watch are different compile legs — `make build` only compiles the iOS Simulator; the macOS slice is checked by `make build-mac`; watch by `make watch-build`. Simulator-backed targets need this worktree's `.simulator_id` and the per-worktree lock; two parallel gates wedge each other without it.
- **Signing**: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch`; without the profile add `-allowProvisioningUpdates`. Never re-derive from `~/Library/Developer/Xcode`.
- **Project file**: `PBXFileSystemSynchronizedRootGroup` — new files under `CheckStitch/`, `CheckStitchCore/`, `CheckStitchTests/`, `CheckStitchWatch/` need no `project.pbxproj` edit.
- **SwiftUI API verification**: the compiler is the oracle — `edit`, then `make build` / `make test-unit` (see the `swiftui-sdk` skill). Read `ContentView.swift`/`CardPlate.swift` precedent before SDK probing.
- **AppleScript/tooling**: scripts live in `scripts/` and `scripts/tests/`, `#!/bin/bash` + `set -euo pipefail`, committed `100755`; shell-linted by the gate via `shellcheck` (warning only if missing).
- **Shell tests coverage** (`scripts/tests/run.sh`): stubs `xcrun`/`defaults`/`make`/`open`/`osascript`; keeps simulator/gate logic testable offline.