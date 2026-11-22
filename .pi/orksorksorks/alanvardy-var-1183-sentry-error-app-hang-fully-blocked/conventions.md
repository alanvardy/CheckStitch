# Conventions & Commands — CheckStitch (VAR-1183 research appendix)

Repo root: `/Users/vardy/dev/alanvardy-var-1183-sentry-error-app-hang-fully-blocked`

## Canonical commands
| Purpose | Command | Where |
|---|---|---|
| Full gate | `./scripts/test.sh` (prints `gate: ok`) | `scripts/test.sh:1-140` |
| Simulator build | `make build` | `Makefile:28-33` |
| macOS unsigned compile | `make build-mac` | `Makefile:41-47` |
| macOS signed app | `make build-mac-signed` | `Makefile:51-57` |
| watchOS compile | `make watch-build` | `Makefile:62-68` |
| widget compile | `make widget-build` | `Makefile:73-78` |
| Unit tests (fast) | `make test-unit` | `Makefile:100-108` |
| UI tests | `make test-ui` | `Makefile:112-123` |
| Both test legs | `make test` (= `test-unit test-ui`) | `Makefile:96` |
| Simulator run | `make run` | `Makefile:91-92` |
| Shell-test harness | `bash scripts/tests/run.sh` | gate calls at `scripts/test.sh:130-132` |

Gate ordering (`scripts/test.sh`): `make build` → acquire simulator lock +
quit Simulator.app (`:57-100`) → pre-boot this worktree's `.simulator_id`
(`:102-107`) → `make test` (`:109`) → release lock (`:110`) → `make build-mac`
(`:113`) → `make watch-build` (`:119`) → `make widget-build` (`:124`) →
`scripts/tests/run.sh` (`:130`) → `shellcheck scripts/*.sh scripts/tests/*.sh
ci_scripts/*.sh` (`:134-140`) → `gate: ok`.

- Destination precedence: explicit `SIM=` > this worktree's `.simulator_id`
  > shared default `name=iPhone 17` (`Makefile:1-8`). Never leave a bare
  `name=` in a script (`AGENTS.md`).
- `make test-unit` uses `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`,
  `-only-testing:CheckStitchTests` (`Makefile:100-108`) — this is the fast
  SentryScrubber/SentryConfiguration test leg.

## Test-suite inventory
| Path | Covers | Platform gating |
|---|---|---|
| `CheckStitchTests/SentryScrubberTests.swift` (84 lines) | Event/breadcrumb PII scrubbing, exception type survival; **no AppHang/stall tests** | macOS host via `test-unit` |
| `CheckStitchTests/SentryConfigurationTests.swift` (36 lines) | DSN trim/blank, PII defaults, env mapping; `@MainActor` | macOS host |
| `CheckStitchTests/PrivacySettingsContentTests.swift` | disclosure names Sentry | macOS host |
| `CheckStitchTests/CrashReportingPreferenceTests.swift` | preference toggle persistence | macOS host |
| `CheckStitchUITests` | one XCTest smoke + UI-testing seam cases | `test-ui`, only class targeted (`Makefile:112-123`) |
| `SingleThreadTests/SentryScrubberTests.swift` (201 lines, precedent) | non-stall PII tests + 9 AppHang system-stall tests (`:85-148`) and frame fixtures (`:151-201`) | SingleThread repo |

- Unit suites use Swift Testing (`@Test`, `#expect`); test targets deliberately
  do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`, so suites opt in with
  `@MainActor` (`AGENTS.md`).
- Fakes live in `CheckStitchTests/TestFixtures.swift`; the Sentry suites build
  events inline instead of using a shared fixture type.

## Warnings-as-errors
- `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` / `GCC_TREAT_WARNINGS_AS_ERRORS=YES` sit
  in project-level Debug+Release configs of `CheckStitch.xcodeproj/project.pbxproj`
  (`Makefile:11-16`); every Xcode build enforces them. `CheckStitchCore` SPM is
  not separately enforced.
- `scripts/tests/run.sh:500` pins
  `WARNINGS_AS_ERRORS_LEGS=(build-mac build test-unit test-ui watch-build widget-build)`;
  `warnings_as_errors_reaches_compiling_legs` (`:525-532`, run `:545`) checks
  the pbxproj settings and that each leg has a Makefile rule. An app-target
  Sentry warning fails the gate.

## Build/verify gotchas
- `beforeSend` frame data is capture-time only: `Frame` exposes `package`
  (`String?`) and `inApp` (`NSNumber?`); function names are unavailable
  (symbolicated server-side) — match on binary-image substrings
  (`SingleThread/SingleThread/SentryScrubber.swift:26-28,35-36,99-104`).
- `inApp` is an SDK-mandated `NSNumber`, read via `.boolValue`; constructing it
  in tests needs `// swiftlint:disable:next legacy_objc_type`
  (`SingleThreadTests/SentryScrubberTests.swift:193-195`).
- Sentry `tracesSampleRate` is set with `NSNumber` (SDK-mandated) behind a
  swiftlint disable (`CheckStitch/SentryBootstrap.swift:22-24`).
- Only `CheckStitch/SentryBootstrap.swift` and `CheckStitch/SentryScrubber.swift`
  may import Sentry in app code; `CheckStitch/SentryConfiguration.swift` is
  deliberately Sentry-free (`SentryConfiguration.swift:3-4`,
  `SentryBootstrap.swift:5-6`).
- sentry-cocoa dependency: remote package `https://github.com/getsentry/sentry-cocoa`,
  `upToNextMajorVersion`, `minimumVersion = 9.26.0`
  (`project.pbxproj:973-980`). Linked only by `CheckStitch` and
  `CheckStitchTests` (`:219-222,:244-247`).
- dSYM upload is Xcode-Cloud-only (`ci_scripts/ci_post_xcodebuild.sh:19-24`),
  not part of the gate.
- New files under `CheckStitch/` need no `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`); new test files under
  `CheckStitchTests/` likewise.
