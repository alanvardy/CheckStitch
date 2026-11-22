I have enough to answer question 1. Writing the report (no write tool available, so returning it here).

---

# Q1 — CheckStitch Sentry init & scrub pipeline, end to end

## Lifecycle / entry points

- `MyApp.init()` calls `SentryBootstrap.startIfEnabled()` before any other setup, gated on `!seams.isUITesting`.
  `CheckStitch/MyApp.swift:42-45` ("Start crash reporting first so no setup work escapes the scrubber").
- The privacy toggle re-invokes the seam: `PrivacySettingsView.swift:25` binds `@AppStorage(CrashReportingPreference.defaultsKey)` (`crashReportingEnabled`, default `true`) and calls `SentryBootstrap.setEnabled(enabled)` in `.onChange` (`PrivacySettingsView.swift:20,25`).
- `setEnabled` either calls `startIfEnabled()` or `SentrySDK.close()` (`SentryBootstrap.swift:43-49`).

## Gate before `SentrySDK.start`

`SentryBootstrap.startIfEnabled()` (`CheckStitch/SentryBootstrap.swift:10-16`):
- Guards on `CrashReportingPreference().isEnabled` and `SentryConfiguration.make(dsn:environment:)` being non-nil.
- `CrashReportingPreference.isEnabled` reads `UserDefaults.standard` key `"crashReportingEnabled"`; missing key → `true` (`CheckStitchCore/Sources/CheckStitchCore/CrashReportingPreference.swift:16-33`).
- `SentryConfiguration.make` trims the DSN and returns `nil` for missing/blank DSN → never calls `start` (`CheckStitch/SentryConfiguration.swift:24-35`). DSN comes from `Bundle.main` `Info.plist` key `SENTRY_DSN` (`SentryBootstrap.swift:52-54`). Environment is `"debug"`/`"production"` by `#if DEBUG` (`SentryConfiguration.swift:9-15`).

## `SentrySDK.start` options (`SentryBootstrap.swift:17-41`)

- `options.dsn`, `options.environment` ← configuration.
- `options.maxBreadcrumbs = UInt(20)`; `options.sendDefaultPii = false`; `options.tracesSampleRate = NSNumber(0)` (all from `SentryConfiguration.make`, `SentryConfiguration.swift:29-32`).
- `enableCrashHandler = true`; `enableAppHangTracking = true`; `enableWatchdogTerminationTracking = true`; `enableAutoSessionTracking = false` (`SentryBootstrap.swift:26-30`).
- iOS/tvOS/visionOS only: `attachScreenshot = false`, `attachViewHierarchy = false` (`SentryBootstrap.swift:33-36`).
- macOS only: `enableUncaughtNSExceptionReporting = true` (`SentryBootstrap.swift:37-39`).
- Closures wired: `options.beforeSend = { SentryScrubber.scrub($0) }`; `options.beforeBreadcrumb = { SentryScrubber.scrub($0) }` (`SentryBootstrap.swift:40-41`). Both are overloads of `scrub` (Event→Event?, Breadcrumb→Breadcrumb?).

## `SentryScrubber.scrub(_ event:) -> Event?` (`CheckStitch/SentryScrubber.swift:16-27`)

Nulled (set to `nil`):
- `event.user`
- `event.extra`
- `event.request`
- `event.modules`
- `event.message`
- `event.transaction`
- each `event.exceptions?.forEach { $0.value = nil }` — exception free-text reason removed (line 25).

Preserved:
- `event.tags` filtered to allow-list `allowedTags = ["environment", "release", "level"]` (line 22; set at `SentryScrubber.swift:13`).
- `event.contexts` untouched (not referenced; documented as SDK device/app metadata only, header comment lines 5-6).
- Exception structural `type` retained (line 25 removes only `value`).

Rebuilt:
- `event.breadcrumbs = event.breadcrumbs?.compactMap(scrub)` — each embedded breadcrumb replaced by the rebuilt `Breadcrumb` (nil ones dropped) (line 26).

Always returns `event` (never nil) — no whole-event drop.

## `SentryScrubber.scrub(_ breadcrumb:) -> Breadcrumb?` (`CheckStitch/SentryScrubber.swift:32-38`)

- Rebuilds a fresh `Breadcrumb(level:category:)`, then copies:
  - `scrubbed.type = breadcrumb.type` (line 35)
  - `scrubbed.timestamp = breadcrumb.timestamp` (line 36)
- Implicitly nulled by non-copy: free-text `message` and the `data` bag are never carried over (line 33-36). Comment notes `data`'s setter is deprecated/read-only so a clean breadcrumb is rebuilt (lines 30-32).
- Always returns the new breadcrumb (no drop; `nil` only reachable in principle — the compactMap handles it).

## Data-flow summary

`MyApp.init` → `SentryBootstrap.startIfEnabled` → `SentrySDK.start { ... }` sets `beforeSend`/`beforeBreadcrumb` → SDK invokes `SentryScrubber.scrub(event)` / `SentryScrubber.scrub(breadcrumb)` at send time → event returned with listed fields nil / tags filtered / breadcrumbs rebuilt via `compactMap`; breadcrumb returned rebuilt. All free-text (user, extra, request, message, transaction, exception.value, breadcrumb.message/data) stripped; structural metadata (exception.type, allow-listed tags, breadcrumb category/type/level/timestamp, contexts) preserved.

## Evidence from tests (`CheckStitchTests/SentryScrubberTests.swift`)

- `reminderContentIsRemovedFromEvent` (lines 8-20): asserts `extra`/`user` nil, `tags["reminderTitle"]` removed, `tags["environment"]=="debug"` survives.
- `reminderContentIsRemovedFromBreadcrumb` (lines 23-36): asserts `message`/`data` nil, `category`/`type` survive.
- `exceptionReasonIsRemovedButTypeSurvives` (lines 57-68): `value` nil, `type` preserved.
- `eventMessageAndTransactionAreRemoved` (lines 70-79): `message`/`transaction` nil.
- `eventWithoutTagsStaysClean`, `breadcrumbWithoutDataSurvives`: nil-safety / non-drop for empty inputs.

### Residual risks / not findable
- `Breadcrumb` overload never appears to return `nil` in current code, so the documented "drop when not allow-listed" behavior is not exercised — nothing in-repo returns `nil`.
- Not inspected: actual sentry-cocoa `beforeSend`/`beforeBreadcrumb` signature nullability and whether `contexts` truly carry no app content at runtime (comment-only claim).