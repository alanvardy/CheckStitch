# Task

Extend CheckStitch's `scripts/run-devices.sh` so it builds and runs the app on
**iPad and macOS as well as the current iPhone-only flow**, following the
reference implementation at `/Users/vardy/dev/SingleThread/scripts/run-devices.sh`.

Today the script builds once for `generic/platform=iOS`, then picks **one**
iPhone-preferred device (the jq filter already accepts iPhone and iPad) and
installs + launches on it. The ticket wants the SingleThread shape instead:
discover **all** Developer-Mode-enabled, reachable iPhone/iPad devices and
install + launch on each, then (by default) build for `platform=macOS` with
`CODE_SIGNING_ALLOWED=NO` and `open` the built `.app` directory on the host Mac.
`RUN_MAC=0` skips the macOS step (default `RUN_MAC=1`, per the reference). If no
iOS devices are found and `RUN_MAC=1`, still do the macOS step; count
unreachable/failed steps and exit non-zero with a summary, mirroring the
reference's failure tally and messaging.

The Xcode project already targets iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) but
does **not** target macOS: the two build-settings blocks
(around lines 282 and 324) have `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`.
Add `macosx` there (→ `"iphoneos iphonesimulator macosx"`), matching
SingleThread's pbxproj. `MACOSX_DEPLOYMENT_TARGET` and `SDKROOT = auto` are
already present. The macOS build must be **unsigned** (`CODE_SIGNING_ALLOWED=NO`) —
signing would need the Mac provisioning profile for the App Group entitlement,
which CheckStitch does not configure (see the reference's header comment and its
`make mac-run` runbook note).

Keep every CheckStitch convention documented in the repo AGENTS.md: plural
`run-devices.sh` name, `#!/bin/bash` + `set -euo pipefail`, committed mode
100755, env overrides `SCHEME`/`BUNDLE_ID` (default `app.alanvardy.CheckStitch`)/
`CONFIGURATION`/`DERIVED_DATA`, `-allowProvisioningUpdates` on the iOS
`xcodebuild`, and never a bare `name=` destination (parallel-agent wedge).
The repo's test gate is `./scripts/test.sh` (build + shellcheck over `scripts/`);
it must keep passing. Do not add a test target.

## Why SMALL

One module, two files touched (`scripts/run-devices.sh` + two identical
`SUPPORTED_PLATFORMS` lines in the pbxproj); the reference implementation
dictates the design end-to-end, so the approach is known with no design
decision, no schema change, no new subsystem, and no shared/convention code
broken — the documented env-override and naming conventions are all preserved.
The test surface is the existing build + shellcheck gate.

## Key files

- `scripts/run-devices.sh` — rewrite to the reference's all-devices + macOS pattern.
- `CheckStitch.xcodeproj/project.pbxproj` — add `macosx` to `SUPPORTED_PLATFORMS`
  in both build settings blocks (~lines 282, 324).
- Reference to port from: `/Users/vardy/dev/SingleThread/scripts/run-devices.sh`
  (and `/Users/vardy/dev/SingleThread/SingleThread.xcodeproj/project.pbxproj`
  for the `SUPPORTED_PLATFORMS` setting).