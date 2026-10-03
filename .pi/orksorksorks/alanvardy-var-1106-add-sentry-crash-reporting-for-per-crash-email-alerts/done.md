# Done

- **Branch / head SHA**: `alanvardy-var-1106-add-sentry-crash-reporting-for-per-crash-email-alerts` @ `74ebb99` (branch is 6 commits ahead of `main`, 0 behind)
- **Mechanical checks**: `./scripts/test.sh` passed end-to-end (`gate: ok`: `make build`, 538 unit tests / 66 suites, 1 UI smoke, `make build-mac`, `make watch-build`, 26/26 shell tests, shellcheck incl. `ci_scripts/*.sh`) — re-run after the applied fixes. `scripts/l10n-check.sh` passed (4 catalogs, 158 keys, 6 languages). No rebase conflicts — the branch was already based on `main`'s tip. Work committed and pushed with `--force-with-lease`.
- **Review outcome**: No blockers. One bounded fresh-context `reviewer` pass plus parent inspection; the port is byte-faithful to the SingleThread reference. Applied (menu [2]):
  - scoped the `SentryScrubber` doc comment and `docs/CrashReporting.md` to exactly the fields stripped, and noted `event.contexts` is SDK metadata only;
  - preserved the structural breadcrumb `type` through the scrubber rebuild (test extended to assert it);
  - `ci_scripts/ci_post_xcodebuild.sh` now uploads `"$CI_ARCHIVE_PATH/dSYMs"` explicitly;
  - restored trailing newlines on 11 new files and the `Makefile`.
  Not applied (deferred): nil'ing `event.contexts`/`threads` wholesale (removes device metadata, hurts grouping); `ci_scripts` `#!/bin/sh` choice (deliberate SingleThread parity).
- **Remaining manual items**: see `review.md` — Xcode (link check), Settings toggle/section + German render, Xcode Cloud `SENTRY_*` env vars, Sentry per-crash email alert, App Store Connect privacy label, and an end-to-end TestFlight Release crash → symbolicated issue + email.

Full review record: `.pi/orksorksorks/alanvardy-var-1106-add-sentry-crash-reporting-for-per-crash-email-alerts/review.md`.