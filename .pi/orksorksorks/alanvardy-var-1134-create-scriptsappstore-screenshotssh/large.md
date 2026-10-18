# Task

Port `/Users/vardy/dev/SingleThread/scripts/appstore-screenshots.sh` (730 lines)
to CheckStitch as `scripts/appstore-screenshots.sh`: per-language captures of
the main list, empty state, settings/options screens and the watch app, in the
App Store Connect display classes (iPhone 6.9"/6.5", iPad 13", Apple Watch),
written to `build/appstore-screenshots/<lang>/<device>/<n>-<name>.png`. The
SingleThread script drives its captures through `--ui-testing*` launch-argument
seams (`--ui-testing-open-settings`, `--ui-testing-open-settings-reminder`,
`--ui-testing-empty`, `--ui-testing-excluded-list`, `--ui-testing-app-language`,
`--seed`, `-showSwipePrompt NO`); CheckStitch has **no** launch seams at all
today (`rg ui-testing` over `*.swift` is empty), so the port has to decide and
build whichever seams CheckStitch needs, on both the iOS and watch targets, then
wire the script into the existing `scripts/*.sh` conventions and the
`scripts/tests/run.sh` stub harness.

## Why LARGE

UNKNOWNS + NEW_SURFACE + CROSS_CUTTING (unknown ordering): the source script is
only reusable once CheckStitch grows a launch-argument seam layer and demo/empty
state seeding in `CheckStitchCore` + `CheckStitch` + `CheckStitchWatch` that does
not exist yet, so the ticket spans UI surfaces, app targets and build/test
tooling with no existing pattern dictating the seams, and the screen/display-
class inventory still needs research.
