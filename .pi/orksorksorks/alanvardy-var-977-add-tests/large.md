# Task

Add a proper test suite to CheckStitch, which currently has no test target at
all. Model the infrastructure on the reference app at
`/Users/vardy/dev/SingleThread` (which has `SingleThreadTests` /
`SingleThreadUITests` / `SingleThreadWatchTests` packages) and write tests for
the app's existing functionality — preferring unit tests over UI tests, and
restructuring the Swift code (ContentView, SettingsView, AppearanceMode, etc.)
to make it more unit-testable as needed. Where appropriate, update this repo's
`AGENTS.md` to require tests going forward (the current file explicitly says
"there is no test target … that is a ticket of its own").

## Why LARGE

UNKNOWNS + NEW_SURFACE + CONVENTION_RISK + CROSS_CUTTING: the repo has zero
test infrastructure today — this introduces a new subsystem (test package,
runner, fixtures, gate integration) with the approach, framework choice,
xcodebuild test-target wiring, and refactor depth all open questions that need
research into SingleThread and likely a spike; it touches the shared
gate/build (scripts/test.sh, Makefile, the xcodebuild scheme with
GENERATE_INFOPLIST_FILE/entitlements) plus all app code plus the repo's
AGENTS.md conventions contract, spanning build/CI, app code, and conventions
with no in-repo pattern dictating the layering.

## Key facts for later steps

- Gate today: `scripts/test.sh` = `make build` + shellcheck over `scripts/*.sh`.
- Reference: `/Users/vardy/dev/SingleThread` — incl. `SingleThreadTests`,
  `SingleThreadWatchTests`, `SingleThreadUITests`, `SingleThreadWatchUITests`
  dirs, a `SingleThreadCore` source package, `TestFixtures.swift` helpers, and
  its `Makefile`/`scripts` for how targets are wired.
- App files under `CheckStitch/` (auto-synced by
  `PBXFileSystemSynchronizedRootGroup`, no pbxproj edit needed for new files):
  `ContentView.swift`, `SettingsView.swift`, `AppearanceMode.swift`,
  `AppDelegate.swift`, `MyApp.swift`.