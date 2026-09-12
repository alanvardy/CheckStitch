# Task

Get CheckStitch (currently an iOS-only Reminders-checklist app: one target,
`ContentView.swift` + `MyApp.swift`) building and running on a real Apple
Watch device, mirroring SingleThread's completed VAR-602 (`SingleThreadWatch`
targets with `SUPPORTED_PLATFORMS = "watchos watchsimulator"` /
`TARGETED_DEVICE_FAMILY = 4`). On-device the app must be able to **run a
checklist** (read items from a CheckStitch Reminders list and let the user
check them off); create/edit/delete are explicitly out of scope for the watch.

## Why LARGE

UNKNOWNS + NEW_SURFACE + CONVENTION_RISK + CROSS_CUTTING: this ports the app
to a brand-new platform target (watchOS) and real watch hardware, touching
shared build/deploy config, with >3 open questions (watchOS EventKit/Reminders
behavior on device, the watch-SwiftUI port of the checklist screen, and the
real-watch devicectl install/launch + signing/entitlements path).

## Key context

- Current iOS-only setup: `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator
  macosx"`, `TARGETED_DEVICE_FAMILY = "1,2"` in
  `CheckStitch.xcodeproj/project.pbxproj`; no watch refs in `Makefile`.
- Mirror precedent (copyable in detail): `/Users/vardy/dev/SingleThread` —
  `SingleThreadWatch{,-Tests,-UITests}` targets, plus its Watch platform
  settings and build/run/deploy scripts.
- Reminders/EventKit reference pattern (required because
  `GENERATE_INFOPLIST_FILE = YES`): `EKReminder` +
  `defaultCalendarForNewReminders()` + `save(commit: true)` per SingleThread.
- Signing: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`,
  App Group `group.app.alanvardy.CheckStitch` (`CheckStitch/AppGroup.entitlements`).
- The branch is currently a bare start commit; the attached GitHub PR #12 is a
  draft shell with no changes.
- The project uses `PBXFileSystemSynchronizedRootGroup` — new source files need
  no pbxproj edit, but a new watch **target** needs proper target entry +
  platform build settings.
- There is no test target; the gate is `./scripts/test.sh` (build + shellcheck).