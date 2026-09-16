# Research Questions

## Context

Focus on the CheckStitch repository's build and verification machinery:
`Makefile`, the `scripts/*.sh` gate and helper scripts, the xcodebuild test
schemes and test suites, and the sibling repository
`/Users/vardy/dev/SingleThread`'s existing CI workflow. Also confirm whether
any CI/automation surface exists in the CheckStitch repo today.

## Questions

1. How is the project gate `scripts/test.sh` structured from start to
   finish: what does it run in what order (make targets, `scripts/tests/run.sh`,
   shellcheck), and exactly which host-local state does each step depend on —
   the per-worktree `.simulator_id`, `resolve-sim-udid.sh`, the lock file in
   `$TMPDIR`, `xcrun simctl boot/bootstatus/shutdown`, `osascript` Simulator
   quit, and default-resolution fallbacks?

2. What does the `Makefile` expose: every target and its exact xcodebuild/
   simctl invocations and flags (`CODE_SIGNING_ALLOWED=NO`,
   `-allowProvisioningUpdates`, `-only-testing`, `build-for-testing` /
   `test-without-building`, destination and `DERIVED_DATA` variables,
   `SIM=` precedence rules), and which targets run unsigned or
   provisioning-free versus which require signing or local device state?

3. What is the test-suite inventory and its platform gating: which test
   targets/suites exist (CheckStitchTests Swift Testing on macOS host, XCTest
   store/codec suites, CheckStitchUITests), where the shared committed schemes
   live and what test-settings they encode (parallelizable, `-only-testing`
   pins), what platform/signing each suite needs, and how `scripts/tests/run.sh`
   stubs host tools (`make`, `xcrun`, `defaults`, `open`) to test the shell
   scripts portably?

4. What does CI look like in the sibling repo `/Users/vardy/dev/SingleThread`:
   the trigger configuration, jobs, runner image, Xcode setup, environment
   variables (`SIM`, `DERIVED_DATA`), signing-off mechanisms on that
   workflow's jobs, simulator pre-boot pattern, caching, and any retry/parallel
   settings — and does the CheckStitch repo itself contain any `.github/`,
   workflow, or dependabot configuration today?