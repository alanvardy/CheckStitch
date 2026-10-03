# Review — VAR-1106 Sentry crash reporting

## Scope

Diff `main...HEAD` (source-only, `.pi/` pipeline artifacts excluded): 26 files,
730 insertions. Feature: port SingleThread's Sentry crash-reporting integration
(sentry-cocoa 9.30.0, inert-when-DSN-empty bootstrap, privacy scrubber, app
privacy manifest, 6-language disclosure + opt-out toggle, Xcode Cloud dSYM
upload, docs).

## Mechanical checks

- `./scripts/test.sh` (the project gate) — **passed**, `gate: ok`:
  `make build` → headless sim pre-boot → `make test` (538 unit tests / 66
  suites + 1 UI smoke) → `make build-mac` → `make watch-build` →
  `scripts/tests/run.sh` (26/26) → shellcheck incl. `ci_scripts/*.sh`.
  Warnings-as-errors confirmed on every compiling leg.
- `scripts/l10n-check.sh` — **passed** (4 catalogs, 158 keys, 6 languages).
- No rebase conflicts: branch already sat on `main`'s tip (0 behind, 5 ahead).
- Work pushed: `8feb895` (artifacts), then `--force-with-lease` push to origin.

## Reviewer

One bounded fresh-context `reviewer` pass over the full source diff
(correctness/robustness, privacy/scrubber, init/lifecycle, pbxproj wiring,
shell scripts, localization/docs).

## Synthesis

### Blockers
None.

### Fixes applied (menu [2])
- `CheckStitch/SentryScrubber.swift` — reworded the doc comment to state exactly
  which free-text fields are stripped and that Sentry `contexts` are left intact
  because they carry SDK device/app metadata only. Also preserves the structural
  breadcrumb `type` through the rebuild; test extended to assert it.
- `docs/CrashReporting.md` — same scope correction, plus the opening line now
  says "the app (iOS and the macOS slice)" instead of "the iOS app target only".
- `ci_scripts/ci_post_xcodebuild.sh` — uploads `"$CI_ARCHIVE_PATH/dSYMs"`
  explicitly rather than the whole `.xcarchive`.
- Trailing newlines restored on 11 new files and the `Makefile`.

All changes re-validated with `./scripts/test.sh` (`gate: ok`, 538 tests / 66
suites, 26/26 shell tests) and `scripts/l10n-check.sh` (ok).

### Fixes considered and not applied
- Nil'ing `event.contexts`/`threads` wholesale — would remove device/os/app
  metadata and can hurt crash grouping/symbolication; no active leak.
- `ci_scripts/*.sh` keep `#!/bin/sh` + `set -eu` (vs the repo's
  `#!/bin/bash` + `set -euo pipefail`) — deliberate SingleThread parity, no
  pipelines, shellcheck-clean.

### Feedback to ignore / defer
- `CrashReportingPreference.init(key: String = defaultsKey)`: legal Swift,
  compiles under the gate. Not an issue.
- `@AppStorage(defaultValue: true)` vs `CrashReportingPreference` absent→true:
  consistent; toggle writes the same `UserDefaults.standard` key. Not an issue.
- `Info.plist $(SENTRY_DSN)` + `ci_post_clone.sh` re-bake: correct — Xcode Cloud
  env vars are not exposed as app-target build settings, so the PlistBuddy `Set`
  is the real bake path. Not an issue.
- `PrivacyInfo.xcprivacy` reason codes: plausible for Sentry's API use, not
  statically verifiable, not gate-checked. Left as-is.

## Port fidelity

`SentryScrubber`, `SentryBootstrap`, `SentryConfiguration`, `ci_scripts/*` are
byte-faithful ports of `/Users/vardy/dev/SingleThread` apart from the
`CheckStitchCore` import rename and the applied review fixes (breadcrumb `type`
preservation, explicit `dSYMs` path, trailing newlines). Sentry is linked to the
`CheckStitch` app + `CheckStitchTests` targets only — `CheckStitchCore`,
`CheckStitchWatch` and `CheckStitchWidget` are untouched.

## Remaining manual items (carried from plan.md)

- Confirm the `Sentry` product is linked only to `CheckStitch` + `CheckStitchTests`
  (Watch/Widget/Core unchanged).
- Settings → Privacy Policy shows the "Crash Reports" toggle + section, with no
  "only network traffic" claim remaining.
- Switching app language to German renders the new section in German.
- Xcode Cloud Environment carries `SENTRY_DSN`/`SENTRY_ORG`/`SENTRY_PROJECT`
  (non-secret) and `SENTRY_AUTH_TOKEN` (secret).
- Configure the Sentry issue alert "email on every new crash".
- Set the App Store Connect privacy label: Diagnostics → Crash Data, Not Linked.
- End-to-end: TestFlight (Release) build → symbolicated Sentry issue + per-crash
  email within minutes.