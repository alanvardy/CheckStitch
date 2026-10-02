# Implementation Summary

Workflow: port SingleThread's Sentry crash-reporting integration into CheckStitch
(Sentry SDK + inert bootstrap + privacy scrubber + consent toggle/privacy manifest/
disclosure copy in 6 languages + Xcode Cloud dSYM upload + docs).

One plan-level blocker was resolved with the operator before Phase 1 could build:
linking `sentry-cocoa` conflicted with CheckStitch's CLI-passed warnings-as-errors
(`-warnings-as-errors` vs `-suppress-warnings`). The operator chose **Option A
(SingleThread parity)**: warnings-as-errors moved from the Makefile CLI into
`project.pbxproj` project-level Debug/Release build configs, the Makefile flag was
removed, the `scripts/tests/run.sh` guards were re-pinned to the pbxproj, and
`AGENTS.md`/`Makefile` comments updated. Consequence (documented, accepted):
`CheckStitchCore` (a local SPM package) is no longer separately warnings-as-errors
enforced — matching SingleThread.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `b92903f` | Dependency + inert Sentry bootstrap + privacy scrubber (+ authorized Option A gate rework) |
| 2     | `f0ab319` | Privacy manifest, disclosure copy, opt-out toggle, and 6-language localization |
| 3     | `6816f4c` | CI dSYM upload, gate shellcheck extension, and crash-reporting docs |

Also committed: `fe54617 chore: remove DELETEME placeholder` (pre-existing, staged
cleanup committed to allow rebase; not a plan phase).

## Automated Checks

- [x] Phase 1: `make build` passes (Sentry resolved from network)
- [x] Phase 1: `make test-unit` passes (incl. SentryConfiguration / SentryScrubber /
      CrashReportingPreference suites; 538 tests / 66 suites)
- [x] Phase 1: `make build-mac` passes (Sentry links on macOS unsigned)
- [x] Phase 1: `make watch-build` passes (Core gained CrashReportingPreference; no Sentry on watch)
- [x] Phase 1: `bash scripts/tests/run.sh` passes (26/26, incl. reworked warnings-as-errors guards)
- [x] Phase 2: `scripts/l10n-check.sh` passes (4 catalogs, 158 keys, 6 languages)
- [x] Phase 2: `make test-unit` passes (disclosure + localization suites)
- [x] Phase 2: `make build` passes
- [x] Phase 3: `./scripts/test.sh` passes end to end (`gate: ok`, 26 shell tests; extended
      shellcheck + bash -n legs cover `ci_scripts/*.sh`)
- [x] Phase 3: `scripts/l10n-check.sh` passes
- [x] Phase 3: `bash -n ci_scripts/ci_post_clone.sh ci_scripts/ci_post_xcodebuild.sh` passes
- [x] Phase 3: `shellcheck scripts/*.sh scripts/tests/*.sh ci_scripts/*.sh` passes clean

## Manual Verification Items (from the plan)

- [ ] Confirm the `Sentry` product is linked only to `CheckStitch` + `CheckStitchTests`
      (inspect the two targets in Xcode; Watch/Widget/Core unchanged)
- [ ] Settings → Privacy Policy shows a "Crash Reports" toggle + section, with no
      "only network traffic" claim remaining
- [ ] Switching app language to German renders the new section in German
- [ ] In Xcode Cloud, confirm the workflow Environment carries `SENTRY_DSN`,
      `SENTRY_ORG`, `SENTRY_PROJECT` (non-secret) and `SENTRY_AUTH_TOKEN` (secret)
- [ ] Configure the Sentry issue alert "email on every new crash" (no filters,
      no threshold, recipient = author email)
- [ ] Set the App Store Connect privacy label: Diagnostics → Crash Data, Not Linked to You
- [ ] End-to-end: on a TestFlight (Release) build, trigger a deliberate error/crash, then
      confirm a symbolicated Sentry issue **and** the per-crash email arrive within minutes

## Notes / observations for the operator

- Phase 3's `docs/CrashReporting.md` deviates slightly from the reference doc, which is
  iOS-only: the macOS-slice bullet states the verified reality (CheckStitch's target
  spans `iphoneos/iphonesimulator/macosx`, shares `CheckStitch/Info.plist` with the DSN,
  and links Sentry; macOS dSYMs aren't uploaded today because no macOS Xcode Cloud archive
  exists). Verified against the code; required by the plan's "including the macOS slice" wording.
- `docs/TestFlight-xcode-cloud.md` also had a now-stale "No ci_scripts/" non-goal, corrected
  as part of Phase 3.
- `CheckStitchCore` warnings-as-errors enforcement was intentionally dropped under the
  approved Option A decision (matching SingleThread, which does not enforce it either).