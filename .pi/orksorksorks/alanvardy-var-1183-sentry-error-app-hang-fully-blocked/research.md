# Research Findings

Repo root: `/Users/vardy/dev/alanvardy-var-1183-sentry-error-app-hang-fully-blocked`
Precedent root: `/Users/vardy/dev/SingleThread`

## Q1: How does CheckStitch's Sentry init and scrub pipeline work end to end?

### Findings
- Entry: `MyApp.init()` calls `SentryBootstrap.startIfEnabled()` first, gated on
  `!seams.isUITesting` — `CheckStitch/MyApp.swift:42-45`.
- `startIfEnabled()` (`CheckStitch/SentryBootstrap.swift:10-16`) guards on
  `CrashReportingPreference().isEnabled` and a non-nil
  `SentryConfiguration.make(dsn:environment:)`, then calls `SentrySDK.start`.
  `setEnabled(_:)` either re-starts or calls `SentrySDK.close()`
  (`SentryBootstrap.swift:43-49`).
- DSN source: `Bundle.main` Info.plist key `SENTRY_DSN`
  (`SentryBootstrap.swift:52-54`); blank DSN → `make` returns `nil` → never
  starts (`CheckStitch/SentryConfiguration.swift:24-35`).
- Options set (`SentryBootstrap.swift:17-41`): `dsn`, `environment`,
  `maxBreadcrumbs=20`, `sendDefaultPii=false`, `tracesSampleRate=0`,
  `enableCrashHandler=true`, `enableAppHangTracking=true`,
  `enableWatchdogTerminationTracking=true`, `enableAutoSessionTracking=false`;
  iOS/tvOS/visionOS `attachScreenshot=false`/`attachViewHierarchy=false`;
  macOS `enableUncaughtNSExceptionReporting=true`.
- Wiring: `options.beforeSend = { SentryScrubber.scrub($0) }` and
  `options.beforeBreadcrumb = { SentryScrubber.scrub($0) }`
  (`SentryBootstrap.swift:40-41`).
- `SentryScrubber.scrub(_ event:) -> Event?`
  (`CheckStitch/SentryScrubber.swift:16-27`) nulls `user`, `extra`, `request`,
  `modules`, `message`, `transaction`, and every `exceptions[].value` (line 25);
  filters `tags` to `allowedTags = ["environment","release","level"]` (line 22,
  set at `SentryScrubber.swift:13`); leaves `contexts` untouched; rebuilds
  `breadcrumbs` via `compactMap(scrub)`. It **always returns `event`** — no
  whole-event drop path exists today.
- `SentryScrubber.scrub(_ breadcrumb:) -> Breadcrumb?`
  (`CheckStitch/SentryScrubber.swift:32-38`) rebuilds `Breadcrumb(level:category:)`
  and copies `type` (line 35) and `timestamp` (line 36); `message`/`data` are
  dropped by non-copy. Returns the new breadcrumb (no drop in practice).
- Privacy toggle drives the live seam from `PrivacySettingsView`
  `@AppStorage(CrashReportingPreference.defaultsKey)` +
  `.onChange → SentryBootstrap.setEnabled(enabled)` (`PrivacySettingsView.swift:16,20-25`).

## Q2: How does SingleThread's SentryScrubber implement its AppHang system-stall drop?

### Findings
- All refs `SingleThread/SingleThread/SentryScrubber.swift` unless noted.
- `struct StackFrameSignature: Equatable { let image: String; let isApp: Bool }`
  at `:11-16`; `init(_ frame: Frame)` extension at `:99-104`:
  `image = frame.package ?? ""`; `isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")`.
- Denylist `systemStallSignatureImages: [String] = ["BackBoardServices", "libxpc.dylib"]`
  at `:29-32` (comment `:21-24`: BackBoardServices/backlight XPC stall; Sentry
  issue 7821993169 via `BKSDisplayBrightnessGetCurrent` → `bootstrap_look_up`).
- `isSystemStall(mechanismType:frames:) -> Bool` at `:41-53`, fail-open
  (returns false on under-specified input):
  1. `guard mechanismType == "AppHang"`;
  2. `guard !frames.isEmpty`;
  3. every denylist image must appear as a substring in some frame;
  4. find first frame matching any denylist image, then require no `.isApp`
     frame in `frames[firstStall...]`.
- `appHangStack(in event:) -> (mechanismType, frames)?` at `:57-68`: selects the
  first exception whose `mechanism?.type == "AppHang"`, requires non-empty
  `stacktrace`, maps frames through `StackFrameSignature.init`.
- `scrub(_ event:)` at `:70-87` runs the drop check first:
  `if let stack = appHangStack(in: event), isSystemStall(...) { return nil }`,
  otherwise the same allow-list scrubbing as CheckStitch.
- Frame names are intentionally unavailable: comment `:26-28,35-36` notes
  sentry-cocoa sets only `package`/`inApp` at capture; symbolication is
  server-side, so matching is on image paths only.

## Q3: What does the Sentry Event/Exception/Mechanism/Frame model expose for hang identification?

### Findings
- Hang identification chain: `Event.exceptions` → first `Exception` with
  `mechanism?.type == "AppHang"` → `Exception.stacktrace.frames` →
  `Frame.package` + `Frame.inApp`.
  `SingleThread/SingleThread/SentryScrubber.swift:60-67,99-104`.
- `Exception.mechanism` (`Mechanism?`), `.stacktrace` (`SentryStacktrace?`),
  `.type` (structural, preserved), `.value` (free text, nulled) —
  `SingleThread/SingleThread/SentryScrubber.swift:60-67,84`.
- `Mechanism` constructed as `Mechanism(type:)`; read via
  `exception.mechanism?.type` (`SingleThread/.../SentryScrubber.swift:61,63`;
  `:44` guards `== "AppHang"`). Comment `:37-38`: `"AppHang"` is the public,
  stable marker; predicate fails open on any other value.
- `SentryStacktrace.frames` is `[Frame]`, required non-empty
  (`SingleThread/.../SentryScrubber.swift:64-65`). Frame fields read are
  exactly `.package` (`String?`) and `.inApp` (`NSNumber?` via `.boolValue`,
  SDK-mandated NSNumber) — `:99-104`. No code reads `frame.function`/`lineNo`/
  `fileName`.
- `Event.threads` exists in the model but is read by **no** code in either
  repo (grep for `.threads` over `*.swift` returns nothing).
- CheckStitch production reads none of these hang fields; it only touches
  `event.exceptions?.value` (`CheckStitch/SentryScrubber.swift:26`).

## Q4: How do the existing Sentry test suites build and assert events?

### Findings
- Two Swift Testing suites per repo, both `import Sentry` + `@testable import <App>`:
  `CheckStitchTests/SentryScrubberTests.swift` (84 lines),
  `CheckStitchTests/SentryConfigurationTests.swift` (36 lines),
  `SingleThreadTests/SentryScrubberTests.swift` (201 lines),
  `SingleThreadTests/SentryConfigurationTests.swift` (47 lines). No Sentry
  tests in either Core package.
- Construction is per-test inline (no custom fixture type in CheckStitch):
  `Event()`, mutate `.extra`/`.user`/`.tags`/`.exceptions`/`.message`/`.transaction`
  (`CheckStitchTests/SentryScrubberTests.swift:9-12,62-65,75-77`); `Exception(value:type:)`
  (`:63-65`); `Breadcrumb(level:category:)` + `.message`/`.setData` (`:24-28`).
- Assertions use Swift Testing `#expect(scrubbed?.field == nil)` for drops
  (`:16`), `#expect(scrubbed != nil)` for survival (`:44`).
- SingleThread system-stall tests (`SingleThreadTests/SentryScrubberTests.swift`):
  `// MARK: App-hang system-stall predicate` at `:85`, `// MARK: Fail-open guarantee`
  at `:109`, `// MARK: Private` `:151`, `// MARK: Fixtures` `:153`.
  - Image constants `appImage`/`swiftUI`/`uiKit`/`coreFoundation`/`libDispatch`/
    `backBoard`/`libXPC`/`libObjCMsgSend` at `:155-167`.
  - `capturedFrames: [(image: String, inApp: Bool)]` — verbatim real-issue stack,
    ~26 tuples, one app frame (`:169-182`).
  - `hangEvent(frames:mechanismType: = "AppHang") -> Event` (`:184-200`) builds
    `Exception(value:"App hanging.", type:"App Hang Fully Blocked")`,
    `Mechanism(type:)`, `SentryStacktrace(frames:registers: [:])`, each `Frame`
    `.package`/`.inApp = NSNumber(value:)`.
  - Drop assertion `#expect(... == nil)` (`:88-90`); keep assertions
    `#expect(... != nil)` (`:97,128,135,142,148`); mixed case asserts survival
    **and** continued PII scrubbing (`:101-107`).
  - Naming: `dropsCapturedBacklightSystemStall`, `keepsHangWithAppFrameInBlockedChain`,
    `keepsNonHangBacklightEvent`, and the fail-open family
    `keepsEventWhenMechanismRenamed`/`StacktraceMissing`/`FrameListEmpty`/
    `DenylistPartiallyMatches`/`AppFrameIsInBlockedChain`/`FramePackageIsMissing`
    (`:87,93,100,112,117,127,131,138,145`).
- CheckStitch's scrubber suite mirrors the non-stall PII tests but has **no**
  `AppHang`/`StackFrameSignature`/`isSystemStall` coverage and no frame fixtures.
- `SentryConfigurationTests` in both repos assert DSN trimming, blank→nil,
  `sendDefaultPii==false`, `tracesSampleRate==0`, `0 < maxBreadcrumbs <= 50`,
  and `#if DEBUG` environment mapping (`CheckStitchTests/SentryConfigurationTests.swift:8-35`).

## Q5: How is Sentry configured in CheckStitch?

### Findings
- `SentryConfiguration` (`CheckStitch/SentryConfiguration.swift:5-17`) is a pure
  `Equatable, Sendable` value type importing no Sentry; `currentEnvironment` is
  `"debug"`/`"production"` by `#if DEBUG` (`:6-14`). `make(dsn:environment:)`
  (`:19-30`) trims the DSN, returns `nil` when blank, and hardcodes
  `maxBreadcrumbs: 20`, `sendDefaultPii: false`, `tracesSampleRate: 0`.
- DSN flow: Xcode Cloud env `SENTRY_DSN` → `PlistBuddy` re-bake in
  `ci_scripts/ci_post_clone.sh:12-14` → `CheckStitch/Info.plist:33-34` token
  `$(SENTRY_DSN)` → `bundleDSN` (`SentryBootstrap.swift:53-55`) →
  `options.dsn` (`:18`). Docs: `docs/CrashReporting.md:18-19,28,33`.
- Environment flow: `SentryConfiguration.currentEnvironment` →
  `options.environment` (`SentryBootstrap.swift:14,19`).
- Opt-in flow: `CrashReportingPreference` (in `CheckStitchCore`) persists
  device-local `UserDefaults` key `crashReportingEnabled` (absent → `true`)
  (`CheckStitchCore/Sources/CheckStitchCore/CrashReportingPreference.swift:19-27`);
  startup guard at `SentryBootstrap.swift:10`; live toggle at
  `PrivacySettingsView.swift:16,23-25`.
- App-hang tracking is explicitly on: `options.enableAppHangTracking = true`
  (`SentryBootstrap.swift:26`); no ANR/`monitorThreadCache` override anywhere.

## Q6: How is code/dependency responsibility divided between app target and CheckStitchCore?

### Findings
- `CheckStitchCore/Package.swift:16-22` declares one target with **no**
  `dependencies:` array (zero SwiftPM deps); sources-only, no `Tests/`
  (`Package.swift:5-6`); platforms iOS 18.7 / macOS 27.0 / watchOS 26.0
  (`:9-13`). No `import Sentry` anywhere in the package.
- `import Sentry` appears in exactly three files, all app-side:
  `CheckStitch/SentryBootstrap.swift:2`, `CheckStitch/SentryScrubber.swift:2`,
  `CheckStitchTests/SentryScrubberTests.swift:2`.
- `CheckStitch/SentryConfiguration.swift:3-4` deliberately imports no Sentry so
  it stays unit-testable; `SentryBootstrap.swift:5-6` documents "the only file
  besides `SentryScrubber` that imports Sentry."
- `project.pbxproj`: local `CheckStitchCore` package ref `:966-969`, remote
  `sentry-cocoa` `https://github.com/getsentry/sentry-cocoa`, `upToNextMajorVersion`,
  `minimumVersion = 9.26.0` (`:973-980`); product deps `:988-992`.
- Targets linking `Sentry`: `CheckStitch` app (`:219-222`, `:137-143`) and
  `CheckStitchTests` (`:244-247`, `:144-150`). Targets linking `CheckStitchCore`
  only (no Sentry): `CheckStitchUITests`, `CheckStitchWatch`, `CheckStitchWidget`
  (`:269-272,:290-293,:313-316`).
- `SentryScrubber` is an app-internal `enum` with `nonisolated static` funcs
  (`CheckStitch/SentryScrubber.swift:12-13,16,32`); tests reach it via
  `@testable import CheckStitch`.

## Cross-Cutting Observations
- CheckStitch has **no** system-stall/AppHang drop logic and no
  `StackFrameSignature`; the only in-app code importing/using Sentry is
  `SentryBootstrap` + `SentryScrubber` (plus their tests). This is the delta
  versus SingleThread's VAR-1165 implementation.
- Both repos share the same Sentry bootstrap shape (`SentryConfiguration` pure
  value type, `beforeSend`/`beforeBreadcrumb` → scrubber, app-hang tracking on).
- Behavioural difference to note: CheckStitch's breadcrumb scrub preserves
  `breadcrumb.type` (`CheckStitch/SentryScrubber.swift:35`); SingleThread's does
  not (`SingleThread/.../SentryScrubber.swift:88-96`).
- The `beforeSend` frame model exposes only `package` and `inApp` (no function
  names) at client capture time — the SingleThread comment `:26-28,35-36`
  establishes this; any signature must match on binary-image substrings.
- Sentry `Event.threads` is unused in both repos; hang detection is driven by
  `Event.exceptions[].mechanism?.type` and its `stacktrace.frames`.
- The reported hang's actual culprit stack (AccessibilitySettingsLoader /
  GuidedAccessManager → `_NSFrameworkPathFromLibraryPath` →
  `-[NSBundle loadAndReturnError:]`) exists only in the ticket (`large.md`); no
  repo artifact captures that stack. The SingleThread denylist
  (`BackBoardServices`, `libxpc.dylib`) targets a *different* stall and does not
  cover it.

## Open Areas
- No in-repo capture of the actual VAR-1183 hang stack or its exact binary-image
  frames; the signature images for this stall are not present in the codebase.
- Whether sentry-cocoa populates `event.threads` with the blocked main-thread
  stack in a way that could be used instead of `exceptions[].stacktrace` was not
  established (no code reads `threads`).
- `Package.resolved` pinning of sentry-cocoa was not inspected.
- The `beforeSend` nullability and whether `contexts` truly carry no app content
  at runtime are comment-only claims, not code-verified.
