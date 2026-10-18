# Task

Port SingleThread's `scripts/appstore-screenshots.sh` to CheckStitch as
`scripts/appstore-screenshots.sh`, producing per-language App Store captures of
the main list, empty state, settings/options screens and the watch app at the
App Store Connect display classes (iPhone 6.9"/6.5", iPad 13", Apple Watch),
written to `build/appstore-screenshots/<lang>/<device>/<n>-<name>.png`.

Because CheckStitch has no launch-argument UI-testing seams today, the port also
has to decide and build whichever seams it needs on both the iOS and watch
targets, then wire the script into the existing `scripts/*.sh` conventions and
the `scripts/tests/run.sh` stub harness.
