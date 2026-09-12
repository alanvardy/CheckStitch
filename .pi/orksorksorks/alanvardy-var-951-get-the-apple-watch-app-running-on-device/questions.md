# Research Questions

## Context

Two SwiftUI codebases are involved: the CheckStitch worktree at
`/Users/vardy/dev/alanvardy-var-951-get-the-apple-watch-app-running-on-device`
(a worktree of `/Users/vardy/dev/CheckStitch`) and the sibling project at
`/Users/vardy/dev/SingleThread`. SingleThread contains a second app target
for a watch platform with its own build/run/test tooling around the
`xcodebuild`/`xcrun` simulator and device tooling already on this machine.
Questions cover: current CheckStitch structure, the SingleThread watch target
declaration, the watch-mode Reminders/EventKit data flow and UI, the
device/simulator deployment and signing tooling available on this machine,
and the shared core layer plus watch test suites.

## Questions

1. How is CheckStitch structured today — its single app target and platform
   build settings, the Reminders/EventKit flow in its UI (entry point,
   store access, reminder creation), the Makefile targets and destination
   logic, and the scripts (run-simulator, run-devices, test gate)?

2. How is SingleThread's watch app target declared in its
   `project.pbxproj` — target entry, per-configuration build settings
   (platforms, device family, deployment target, infoplist keys,
   entitlements), and how its source files are included (file refs,
   synchronized-root groups, or build phases)? What are the corresponding
   watch build/test Makefile targets and their destination variables?

3. How does SingleThread's watch app read from and write to Reminders
   (EventKit) and render the UI — the watch entry point, view models,
   reminder views and state files, the EKReminder / event-store /
   defaultCalendarForNewReminders / save(commit:) usage, and what the
   Watch companion-identifier and watch-only infoplist keys say about how
   the watch app relates to its iOS companion?

4. What device and simulator deployment, launch, and signing tooling
   exists on this machine for watch apps — `xcrun devicectl` and `simctl`
   capabilities relevant to watch OS devices or the watchOS Simulator
   (device listing, install, launch, destination identifiers), and how
   watch app bundles are signed/entitled (DEVELOPMENT_TEAM, CODE_SIGN
   entitlements, infoplist requirements)?

5. What does SingleThread share between its iOS and watch targets
   (the shared core package, its Reminders/EventKit code paths) and what
   are the watch test suites (`SingleThreadWatchTests`,
   `SingleThreadWatchUITests`) — what they cover and how they build and run
   on the watch simulator?