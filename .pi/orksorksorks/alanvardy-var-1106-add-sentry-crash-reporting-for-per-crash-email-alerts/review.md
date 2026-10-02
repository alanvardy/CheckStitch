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

### Fixes worth doing now
- `CheckStitch/SentryScrubber.swift:6-8` + `docs/CrashReporting.md` — the
  "strips every free-text field that could carry checklist/reminder content"
  wording overclaims: the scrubber does not touch `event.contexts` or stack-frame
  locals. Neither carries app content today (no app code populates contexts;
  sentry-cocoa does not capture frame locals by default), so the shipped
  invariant holds, but the doc/comment should be scoped to what it actually
  strips (user/extra/request/message/transaction/exception reasons/breadcrumb
  message+data). Documentation-only, zero behaviour change.

### Optional improvements
- `ci_scripts/ci_post_xcodebuild.sh:24-27` — pass `"$CI_ARCHIVE_PATH/dSYMs"`
  explicitly instead of the whole `.xcarchive` for determinism (sentry-cli does
  walk xcarchives, and this matches the SingleThread reference as-is).
- `CheckStitch/SentryScrubber.swift:33-34` — breadcrumb rebuild drops `type`;
  keeping it would preserve auto-breadcrumb grouping without free text.
- Missing trailing newlines on new Swift/CI files and on `Makefile` (the
  `clean:` target lost its final newline); cosmetic git noise.
- `ci_scripts/*.sh` use `#!/bin/sh set -eu` vs the repo convention
  `#!/bin/bash set -euo pipefail` — deliberate (plan Q2, SingleThread parity,
  shellcheck-clean, no pipelines).

### Feedback to ignore / defer
- `event.contexts`/`threads` not nil'd: nil'ing them wholesale would remove
  device/os/app metadata and can hurt crash grouping/symbolication; no active
  leak, and the task mandates the SingleThread pattern. Defer.
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
`CheckStitchCore` import rename and missing trailing newlines. Sentry is linked
to the `CheckStitch` app + `CheckStitchTests` targets only — `CheckStitchCore`,
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