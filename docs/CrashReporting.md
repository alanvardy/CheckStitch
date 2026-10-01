# Crash Reporting (Sentry)

CheckStitch links [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) on the iOS app
target only (the macOS slice is deliberate — see below). It is steered through
`SentryConfiguration` (a pure, Sentry-free value type) and `SentryBootstrap` (the only place
besides `SentryScrubber` that imports Sentry). All events and breadcrumbs pass through
`SentryScrubber`, which strips every free-text field that could carry checklist/reminder content —
user, extra, request, message, transaction, exception reasons, and breadcrumb message/data — and
keeps only structural metadata (exception type, allow-listed tags, breadcrumb category/level/
timestamp). The feature ships inert (empty DSN) until Xcode Cloud supplies the real DSN.

## Sentry org setup

- Use the **US data region** and the **free Developer plan** (per-crash email alerts are included
  on that plan). If the region/plan differs, only the DSN host and dashboard change — no code.
- The DSN lives **only** in the Xcode Cloud workflow Environment as `SENTRY_DSN` (non-secret). It
  is baked into the app's `Info.plist` at build time (via the `$(SENTRY_DSN)` build-setting token,
  and re-baked by `ci_scripts/ci_post_clone.sh`). No credential is committed to the repo.

## Xcode Cloud Environment

Set these in the Xcode Cloud workflow Environment:

| Variable | Secret | Purpose |
|---|---|---|
| `SENTRY_DSN` | no | Baked into `Info.plist`; enables the reporter |
| `SENTRY_ORG` | no | dSYM upload |
| `SENTRY_PROJECT` | no | dSYM upload |
| `SENTRY_AUTH_TOKEN` | **yes** | dSYM upload (sentry-cli auth) |

Locally / in normal CI without `SENTRY_DSN`, `$(SENTRY_DSN)` expands to an empty string and
`SentryConfiguration.make` returns `nil`, so `SentrySDK.start` is never called.

## Alert rule

To be alerted per crash, in Sentry create an **issue alert** "email me on every new crash": all
events, no filters and no severity threshold, recipient = the author's email. This is dashboard
configuration and is not gate-testable.

## Triage steps

1. Open Sentry → Issues and filter the failed release.
2. Confirm the crash is **symbolicated** (the dSYM UUID matches the shipped build — see
   `sentry-cli debug-files list` for the uploaded UUIDs).
3. Read the stack trace, reproduce locally, file/fix in Linear, then mark the event Resolved.

## dSYM upload

- `ci_scripts/ci_post_xcodebuild.sh` uploads the archived dSYMs with `sentry-cli debug-files
  upload` whenever an Xcode Cloud archive runs with the Sentry credentials set. It is a no-op for
  non-archive builds and when the credentials are absent.
- A late dSYM upload (after a crash report was recorded) needs **event reprocessing** in Sentry to
  symbolicate the already-recorded events.
- **Debug builds use `dwarf`** (`DEBUG_INFORMATION_FORMAT = dwarf` keeps incremental builds fast),
  so only Release / Xcode Cloud archives produce symbolicated crashes. Deliberate crash testing on
  a Debug simulator build will show an unsymbolicated stack in the dashboard — use a Release build
  to verify symbolication end to end.
- The **macOS slice** shares the CheckStitch target (`SUPPORTED_PLATFORMS = iphoneos
  iphonesimulator macosx`) and the same `CheckStitch/Info.plist`, so it links Sentry and bakes the
  same `$(SENTRY_DSN)`. There is no macOS workflow/archive in Xcode Cloud yet (see the TestFlight
  doc's *macOS fast-follow*), so the macOS app's dSYMs are not uploaded today — the dSYM upload
  covers the iOS archive. Re-enable the macOS upload path when a macOS release pipeline exists.