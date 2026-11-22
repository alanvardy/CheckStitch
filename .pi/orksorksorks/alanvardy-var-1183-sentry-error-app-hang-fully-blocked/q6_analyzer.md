Per the fish-guard rule (on a rejection, stop — do not retry a variant) I am not retrying the file write. Returning the artifact text in the final message.

---

# Q6 — Responsibility split: `CheckStitch` app target vs `CheckStitchCore` SPM package

## 1. What the local package can depend on
- `CheckStitchCore/Package.swift:5-6` — comment: "Sources only: the package is tested by the app-hosted CheckStitchTests target (`@testable import CheckStitchCore`), never by `swift test` — no Tests/ dir." Confirmed by `find`: only `Package.swift` + `Sources/CheckStitchCore/*.swift`.
- `CheckStitchCore/Package.swift:16-22` — one `.target(name: "CheckStitchCore", resources: [.process("Resources")])` with **no** `dependencies:` array → the package declares zero SwiftPM dependencies.
- Search for `Sentry` in `CheckStitchCore/Package.swift` → no matches.
- Search for `Sentry` under `CheckStitchCore/` → one hit, in a doc comment only: `CheckStitchCore/Sources/CheckStitchCore/CrashReportingPreference.swift:19-20` ("Single shared key used by the settings toggle and `SentryBootstrap`"). No `import Sentry` anywhere in the package.
- Platforms `Package.swift:9-13`: iOS 18.7 / macOS 27.0 / watchOS 26.0 — the package is shared by app, tests, watch and widget targets.

## 2. Which targets import or link Sentry
`import Sentry` appears in exactly three files, all outside the package:
- `CheckStitch/SentryBootstrap.swift:2` (plus `:3 import CheckStitchCore`)
- `CheckStitch/SentryScrubber.swift:2`
- `CheckStitchTests/SentryScrubberTests.swift:2` (with `:3 @testable import CheckStitch`)

Deliberately Sentry-free: `CheckStitch/SentryConfiguration.swift:3-4` — "Pure description of the crash-reporting configuration. Imports no Sentry so it stays unit-testable; `SentryBootstrap` maps it to `SentryOptions`." `SentryBootstrap.swift:5-6` restates the invariant — "The only file besides `SentryScrubber` that imports Sentry." `CheckStitchTests/SentryConfigurationTests.swift:1-3` imports only Foundation + `@testable import CheckStitch`.

Linking (`CheckStitch.xcodeproj/project.pbxproj`):
- Project-scope `packageReferences` `:362-365` = local `CheckStitchCore` (`:966-969`, `relativePath = CheckStitchCore`) + `XCRemoteSwiftPackageReference "sentry-cocoa"` (`:973-980`: `https://github.com/getsentry/sentry-cocoa`, `upToNextMajorVersion`, `minimumVersion = 9.26.0`).
- Product dependency `Sentry` `:988-992` (`productName = Sentry`); local product `:984-987`.
- `PBXBuildFile` Sentry entries only two: `:17-18` (`.092`, `.093 /* Sentry in Frameworks */`).
- Targets that link it:
  - `CheckStitch` (app): `packageProductDependencies` `:219-222`; Frameworks phase `:137-143` (`.060 CheckStitchCore`, `.092 Sentry`).
  - `CheckStitchTests` (unit-test bundle): `packageProductDependencies` `:244-247`; Frameworks phase `:144-150` (`.061 CheckStitchCore`, `.093 Sentry`).
- Targets that link **CheckStitchCore only**, no Sentry:
  - `CheckStitchUITests`: `:269-272`; Frameworks phase `:151-156` (`.062`).
  - `CheckStitchWatch`: `:290-293`; Frameworks phase `:157-162` (`.063`).
  - `CheckStitchWidget`: `:313-316`; Frameworks phase `:163-168` (`.065`).

## 3. Resulting split (data flow)
- The app target owns the whole SDK surface. `SentryBootstrap.startIfEnabled()` reads the DSN from `Info.plist` (`SentryBootstrap.swift:53-55`), guards on `CrashReportingPreference().isEnabled` and `SentryConfiguration.make(dsn:environment:)` returning non-nil (`:11-16`), then `SentrySDK.start` (`:17-40`) wiring `options.beforeSend = { SentryScrubber.scrub($0) }` / `beforeBreadcrumb` (`:38-39`). `setEnabled(_:)` calls `startIfEnabled()` or `SentrySDK.close()` (`:43-49`).
- Only call sites are app-target files: `CheckStitch/MyApp.swift:43` and `CheckStitch/PrivacySettingsView.swift:25`.
- The one crash-reporting thing the package exposes is plain `UserDefaults` state, naming no Sentry type: `CrashReportingPreference.swift:9-35` (key `:20`, `isEnabled` `:23-25`, `setEnabled` `:27-29`). Its header `:5-8` states the boundary: "Device-local by design: the watch and widget must not acquire the crash reporter, so this key is deliberately *not* in the App Group and is not synced over WatchConnectivity." This matches §2 — watch/widget link `CheckStitchCore` only.
- `SentryScrubber` is an app-internal `enum` with `nonisolated static` funcs (`SentryScrubber.swift:13`, `:16`, `:32`); tests reach it via `@testable import CheckStitch`, not through the package.

## 4. What build/test/gate commands imply for Sentry-touching code
- `make build` (scheme `CheckStitch`, simulator) `Makefile:26-31`; gate calls it at `scripts/test.sh:53`.
- `make test` = `test-unit` + `test-ui` (`Makefile:96`). `test-unit` runs `-only-testing:CheckStitchTests` on `platform=macOS` with `CODE_SIGNING_ALLOWED=NO` (`Makefile:100-108`) — that leg executes `SentryScrubberTests`/`SentryConfigurationTests` on the macOS host. `test-ui` uses this worktree's simulator (`Makefile:112-123`), invoked at `scripts/test.sh:111`.
- `make build-mac` `Makefile:38-44`, `make watch-build` `Makefile:49-53` (builds `CheckStitchWatch`, which links no Sentry), `make widget-build` `Makefile:58-63`; the gate runs them at `scripts/test.sh:120-128`, then `scripts/tests/run.sh` (`:130-132`), then shellcheck over `scripts/*.sh scripts/tests/*.sh ci_scripts/*.sh` (`:134-140`).
- Warnings-as-errors: `Makefile:11-16` — `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` / `GCC_TREAT_WARNINGS_AS_ERRORS=YES` live in project-level Debug/Release configs of the pbxproj so every Xcode build enforces them, and "The CheckStitchCore local SPM package is not separately enforced." Gate pin: `scripts/tests/run.sh:500` `WARNINGS_AS_ERRORS_LEGS=(build-mac build test-unit test-ui watch-build widget-build)`, enforced by `warnings_as_errors_reaches_compiling_legs` (`:525-532`, run at `:545`) which checks the pbxproj settings and that each leg has a Makefile rule (`:529-531`). Net effect: an app-target Sentry warning fails the gate directly; a package warning surfaces only through a leg that compiles the package (all gate legs do).
- No leg runs `swift build`/`swift test` on `CheckStitchCore`, consistent with `Package.swift:5-6`.
- Sentry tooling outside the SDK is dSYM upload only: `ci_scripts/ci_post_clone.sh:4-6` (installs `sentry-cli`) and `ci_scripts/ci_post_xcodebuild.sh:19-24` (`sentry-cli debug-files upload`, skipped when absent). Xcode Cloud only, not part of `scripts/test.sh`.

## 5. Not established within budget
- Whether a committed `Package.resolved` pins sentry-cocoa resolution (not inspected).
- Note: one earlier `rg` invocation of mine used `-r` and rendered "nBootstrap"; the actual file text at `CrashReportingPreference.swift:19-20` reads `SentryBootstrap`.

---