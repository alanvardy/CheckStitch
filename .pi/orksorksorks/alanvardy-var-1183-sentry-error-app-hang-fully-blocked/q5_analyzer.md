I have enough to answer question 5. (No write tool is available, so the report is returned in this final message for the runtime to persist to `q5_analyzer.md`.)

## Q5 — Sentry configuration in CheckStitch

### Pure value type: `SentryConfiguration`
`CheckStitchCore`-independent, no Sentry import, "pure description of the crash-reporting configuration" — `CheckStitch/SentryConfiguration.swift:3-5`.

Fields (`SentryConfiguration.swift:5-17`):
- `static var currentEnvironment: String` — build-config-derived: `#if DEBUG → "debug"` else `"production"` (`:6-14`).
- `let dsn, environment: String; maxBreadcrumbs: Int; sendDefaultPii: Bool; tracesSampleRate: Double` (`:15-17`).

Factory `make(dsn:environment:) -> Self?` (`SentryConfiguration.swift:19-30`):
- Trims whitespace/newlines; `nil` if missing/blank → "never call `SentrySDK.start`" (`:19-23`).
- Hardcoded constants: `maxBreadcrumbs: 20`, `sendDefaultPii: false`, `tracesSampleRate: 0` (`:27-29`).
- `Equatable, Sendable` (`:5`).

### Options applied in `SentryBootstrap`
`SentryBootstrap` is described as the "Thin adapter from `SentryConfiguration` to `SentrySDK`. The only file besides `SentryScrubber` that imports Sentry" — `CheckStitch/SentryBootstrap.swift:5-7`.

Gate `startIfEnabled()` (`SentryBootstrap.swift:9-16`): `guard CrashReportingPreference().isEnabled, let configuration = SentryConfiguration.make(dsn: bundleDSN, environment: SentryConfiguration.currentEnvironment) else { return }`.

Then `SentrySDK.start { options in ... }` sets (`SentryBootstrap.swift:17-40`):
- `options.dsn = configuration.dsn` (`:18`)
- `options.environment = configuration.environment` (`:19`)
- `options.maxBreadcrumbs = UInt(configuration.maxBreadcrumbs)` (`:20`)
- `options.sendDefaultPii = configuration.sendDefaultPii` (`:21`) — i.e. `false`
- `options.tracesSampleRate = NSNumber(value: configuration.tracesSampleRate)` with `// swiftlint:disable:next legacy_objc_type` — SDK-mandated NSNumber (`:22-24`); value `0`
- `options.enableCrashHandler = true` (`:25`)
- **App-hang tracking**: `options.enableAppHangTracking = true` (`:26`)
- **Watchdog termination**: `options.enableWatchdogTerminationTracking = true` (`:27`)
- **Auto session tracking**: `options.enableAutoSessionTracking = false` (`:28`)
- Screenshot/hierarchy attaches `= false`, wrapped in `#if os(iOS) || os(tvOS) || os(visionOS)` because "sentry-cocoa does not declare them for macOS" (`:29-34`)
- `#if os(macOS) options.enableUncaughtNSExceptionReporting = true` (`:35-37`)
- `options.beforeSend = { SentryScrubber.scrub($0) }` (`:38`)
- `options.beforeBreadcrumb = { SentryScrubber.scrub($0) }` (`:39`)

Toggle path `setEnabled(_:)` (`SentryBootstrap.swift:42-49`): `true → startIfEnabled()`, `false → SentrySDK.close()`.

### How DSN reaches the SDK
- `bundleDSN` reads Info.plist key `SENTRY_DSN`: `Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String` (`SentryBootstrap.swift:53-55`, cited `:54`).
- `Info.plist` holds the token `<key>SENTRY_DSN</key><string>$(SENTRY_DSN)</string>` (`CheckStitch/Info.plist:33-34`).
- Build-time re-bake: `ci_scripts/ci_post_clone.sh:12-14` runs `PlistBuddy -c "Set :SENTRY_DSN $SENTRY_DSN" CheckStitch/Info.plist` when the env var is present. Docs: DSN lives only in Xcode Cloud workflow Environment as `SENTRY_DSN`, non-secret, baked via the `$(SENTRY_DSN)` token (`docs/CrashReporting.md:18-19,28,33`).
- So: env `SENTRY_DSN` → Info.plist token → `bundleDSN` (`:54`) → `SentryConfiguration.make` → `options.dsn` (`:18`). Empty locally → `make` returns nil → no start.

### How environment reaches the SDK
Compile-time `SentryConfiguration.currentEnvironment` (`SentryConfiguration.swift:6-14`) passed into `make` and set as `options.environment` (`SentryBootstrap.swift:14,19`).

### How the crash-reporting opt-in reaches the SDK
- Preference type `CrashReportingPreference` in `CheckStitchCore/Sources/CheckStitchCore/CrashReportingPreference.swift` persists in `UserDefaults.standard` (`:1-24`); deliberately device-local, **not** in App Group / not WatchConnectivity-synced so watch/widget don't acquire the reporter (`:8-10`). Key `crashReportingEnabled` (`:19`); `isEnabled` = `defaults.object(forKey:) as? Bool ?? true` — absent → `true` (`:22-23`); `setEnabled` writes (`:25-27`).
- Startup: `MyApp.swift` init calls `SentryBootstrap.startIfEnabled()` (guarded by `if !seams.isUITesting`), "Start crash reporting first so no setup work escapes the scrubber" (`CheckStitch/MyApp.swift:39-43`).
- Settings toggle: `PrivacySettingsView` `@AppStorage(CrashReportingPreference.defaultsKey) private var crashReportingEnabled = true` (`CheckStitch/PrivacySettingsView.swift:16`), and `.onChange(of:) { _, enabled in SentryBootstrap.setEnabled(enabled) }` (`:23-25`).
- So opt-in flows: UserDefaults key → `CrashReportingPreference().isEnabled` guard (`SentryBootstrap.swift:10`) at start; live toggle → `setEnabled` → start/close (`:42-49`, called from `PrivacySettingsView.swift:24`).

### Test corroboration
`SentryConfigurationTests` (`CheckStitchTests/SentryConfigurationTests.swift`) asserts: DSN trimmed (`:9-11`), blank/nil DSN → nil (`:15-17`), safe privacy defaults — `sendDefaultPii == false`, `tracesSampleRate == 0`, `0 < maxBreadcrumbs <= 50` (`:22-25`), and `currentEnvironment` Debug/Release mapping (`:28-33`). Tests use `@testable import CheckStitch` + `@MainActor` (`:1-4`).

### Notes / not found in budget
- Where `$(SENTRY_DSN)` build setting is defined in `project.pbxproj` (the token's value source) was not read this pass; the docs state it comes from the Xcode Cloud workflow Environment. Not required for this question.