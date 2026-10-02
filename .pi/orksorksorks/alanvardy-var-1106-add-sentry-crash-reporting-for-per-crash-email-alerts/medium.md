# Task

Add Sentry (`sentry-cocoa`) crash/error reporting to the CheckStitch iOS+macOS
app target so a production crash yields a symbolicated Sentry issue **and** a
per-crash email within minutes — replacing today's zero crash visibility. This
is the repo's first third-party dependency, first `*.xcprivacy`, and first
Xcode Cloud post-action scripts. Privacy is invariant: `sendDefaultPii = false`,
`tracesSampleRate = 0`, session tracking off, and no checklist content (names,
notes, item text) may ever reach a breadcrumb, message, tag, or extra.

**This exact task is already implemented and shipped in
`/Users/vardy/dev/SingleThread`** — port that pattern, don't re-derive it.

- **Dependency** — add the `sentry-cocoa` remote package to the project,
  linked to the `CheckStitch` target only (never `CheckStitchCore`, which
  would propagate to watch/widget).
- **Init** — `SentrySDK.start` from the app entry (and `AppDelegate.swift` if
  a UIKit hook is required), driven by a pure, Sentry-free options factory
  (`SentryConfiguration.make` in SingleThread) that is **inert when the DSN is
  empty** (`dsn` read from `Info.plist` via a `$(SENTRY_DSN)` build-setting
  token) so local/Debug and non-DSN CI stay off. Port `SentryBootstrap` (the
  only non-scrubber file that imports Sentry) to map the factory to `SentryOptions`.
- **Privacy scrubber** — port `SentryScrubber`: allow-list tags
  (`environment`, `release`, `level`), `nil` out `user/extra/request/modules/
  message/transaction`, clear `Exception.value`, and rebuild breadcrumbs with
  only category/level/timestamp. Applied via `beforeSend`/`beforeBreadcrumb`.
- **Privacy manifest** — add `PrivacyInfo.xcprivacy` for the app (Sentry has
  its own; the app's manifest must declare what it collects and already-used
  required-reason APIs).
- **Copy + store label** ⚠️ — update `CheckStitch/PrivacySettingsContent.swift`
  (which claims data is "never sent to the author or any third party" — Sentry
  falsifies that), README/marketing copy, and the App Store Connect privacy
  label (Diagnostics → Crash Data, Not Linked to You). New/changed user-facing
  strings go through `Localizable.xcstrings` with **all 6 languages** (SingleThread
  shipped 5 — CheckStitch needs its 6th too) plus a `LocalizationFixtures.requiredKeys`
  entry; `scripts/l10n-check.sh` must pass.
- **Symbolication / CI** — port `ci_scripts/ci_post_clone.sh` (`brew install
  sentry-cli` + bake DSN into Info.plist) and `ci_scripts/ci_post_xcodebuild.sh`
  (`sentry-cli debug-files upload --org --project "$CI_ARCHIVE_PATH"` when
  `CI_ARCHIVE_PATH` and `SENTRY_*` creds are set; no-op otherwise). Sentry
  creds live in Xcode Cloud workflow Environment (DSN/ORG/PROJECT non-secret,
  AUTH_TOKEN secret) — never in the repo. `DEBUG_INFORMATION_FORMAT` stays
  `dwarf` Debug / `dwarf-with-dsym` Release, so only Release archives symbolicate.
- **Alert rule** — Sentry issue alert, "email on new crash", no filters/threshold,
  recipient = author email (dashboard config, not gate-testable). Verify
  end-to-end with a deliberately thrown error on a TestFlight build.
- **Tests** — port `SentryConfigurationTests`, `SentryScrubberTests`, and a
  `PrivacySettingsContentTests` (Swift Testing, `@testable import CheckStitch`,
  `@MainActor` as needed). Confirm the privacy-critical constants and that
  checklist content never reaches an event/breadcrumb.
- **Docs** — extend `docs/TestFlight-xcode-cloud.md` (or a sibling doc) with the
  dSYM-upload step and the Sentry org setup.

SingleThread differences to resolve while porting: it targets iOS-app-only and
its Localizable has only 5 languages (CheckStitch needs 6); CheckStitch's
`scripts/*.sh` are `#!/bin/bash` with `set -euo pipefail` and shellcheck runs on
`scripts/*.sh scripts/tests/*.sh` — decide (and state in the PR) whether the
gate's shellcheck leg extends to `ci_scripts/*.sh` or whether those scripts sit
outside enforcement like `build-mac-signed`/`run-devices.sh`. SingleThread's
ci_scripts are `#!/bin/sh`; keep that choice consistent. Gate must pass:
`./scripts/test.sh` (→ `make build` → `make test` → `make build-mac` →
`make watch-build` → `scripts/tests/run.sh` → `shellcheck`,
`WARNINGS_AS_ERRORS` on every swift leg).

## Why MEDIUM

Breadth triggers matched — **MULTI_MODULE** (dependency wiring, app-init,
options factory, scrubber, `*.xcprivacy`, privacy copy + 6-language
localization, `ci_scripts/*.sh`, `Info.plist`, unit tests, docs — well over 5
files across dependency/build/UI/CI surfaces) and **CROSS_CUTTING, known
ordering** (#9: a prior ticket/impl — SingleThread's Sentry integration — did
this exact shape end to end, so the existing pattern dictates layering and
sequence). M1 holds (approach fully known; all research — sentry-cocoa version,
`SentryOptions` surface, Xcode Cloud dSYM upload, `ci_post_clone.sh` install —
is already done in SingleThread) and M2 holds (no schema/migration; every open
trade-off — scope, US region, free Developer plan, alert rule, inert-DSN
pattern — is resolved by SingleThread precedent; nothing needs human sign-off).
One `medium-plan` step (light recon → `plan.md`) precedes the implement→review
tail; no research fan-out, no design doc, one human gate.

## Key files

Port the following from `/Users/vardy/dev/SingleThread`:
- `SingleThread/SentryConfiguration.swift` → pure options factory (mirror for CheckStitch)
- `SingleThread/SentryBootstrap.swift` → the only Sentry-importing init file
- `SingleThread/SentryScrubber.swift` → `beforeSend`/`beforeBreadcrumb` redaction
- `SingleThread/SingleThreadApp.swift` (`SentryBootstrap.startIfEnabled()`)
- `SingleThread/PrivacyInfo.xcprivacy` → app privacy manifest
- `SingleThread/PrivacySettingsContent.swift` + its test → privacy copy
- `ci_scripts/ci_post_clone.sh`, `ci_scripts/ci_post_xcodebuild.sh` → Xcode Cloud dSYM upload
- `SingleThread/Info.plist` `$(SENTRY_DSN)` token pattern
- `SingleThreadTests/SentryConfigurationTests.swift`, `SentryScrubberTests.swift`,
  `PrivacySettingsContentTests.swift`, `docs/CrashReporting.md`

CheckStitch targets to change: `CheckStitch/MyApp.swift` (+ `AppDelegate.swift`
if needed), `CheckStitch/PrivacySettingsContent.swift`, `CheckStitchCore` must
**not** gain the dependency, `project.pbxproj` `packageReferences`,
`Localizable.xcstrings` (6 languages) + `LocalizationFixtures.requiredKeys`,
new `ci_scripts/`, `docs/TestFlight-xcode-cloud.md`.