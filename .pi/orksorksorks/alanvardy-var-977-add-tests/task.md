# Task

Add a proper test suite to CheckStitch, which currently has no test target at
all. Model the infrastructure on the reference app at
`/Users/vardy/dev/SingleThread` (which has separate test packages) and write
tests for the app's existing functionality — preferring unit tests over UI
tests, and restructuring the Swift code (ContentView, SettingsView,
AppearanceMode, etc.) to make it more unit-testable as needed. Where
appropriate, update this repo's `AGENTS.md` to require tests going forward
(the current file explicitly says "there is no test target … that is a ticket
of its own").

Today the gate is `scripts/test.sh` = `make build` + shellcheck over
`scripts/*.sh`; the project uses `PBXFileSystemSynchronizedRootGroup` (new
files under `CheckStitch/` need no `project.pbxproj` edit) and
`GENERATE_INFOPLIST_FILE = YES` with `NSReminders*UsageDescription` keys.