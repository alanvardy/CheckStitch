# Research Questions

## Context

CheckStitch is a Swift/SwiftUI iOS app ("CheckStitch") with a
Makefile/xcodebuild build system, local dev targets for simulator, macOS,
and watchOS, signing via a development team plus an entitlements file, and a
shell-script test gate. There is no CI, no release/distribution
scaffolding, and no GitHub Actions anywhere in the repo. The research
focuses on the build pipeline, signing configuration, project
configuration, the gate infrastructure, and app-level configuration — the
full existing build/release surface a distribution integration would build
on.

## Questions

1. Trace the build pipeline from the Makefile and scripts: what targets,
   xcodebuild invocations, destinations, and configurations exist, and what
   iOS artifacts do they produce at which paths? Include how the simulator,
   device, and macOS flavors differ and how scripts resolve simulator
   destinations.

2. What is the signing/entitlements configuration across all build
   targets? Cover the development team, bundle identifier, App Group,
   entitlements file contents, CODE_SIGN_* settings, provisioning flags
   (-allowProvisioningUpdates), and the infoplist usage keys, noting which
   targets are signed vs unsigned and any platform differences.

3. How is the Xcode project organized: targets, build configurations,
   platform settings (SDKROOT, SUPPORTED_PLATFORMS, TARGETED_DEVICE_FAMILY),
   build products, versions, and the shared scheme files? How do the
   schemes make xcodebuild test deterministic?

4. How does the gate script (scripts/test.sh) work end to end: what does it
   run, what does it depend on (simulator UDID resolution, host lock,
   Simulator.app handling, environment variables), and what do the shell
   tests (scripts/tests/run.sh) stub and verify? What environment would a
   headless CI run need to reproduce it?

5. What is the app-level configuration surface: bundle id, MARKETING_VERSION,
   infoplist settings, App Group / KVS usage keys, and how does the
   reference SingleThread app configure its Reminders/EventKit integration
   (EKReminder, defaultCalendarForNewReminders, NSReminders usage keys)?
   Also cover the watch target's differing bundle id and signing state.

6. How does the SingleThread reference app (at /Users/vardy/dev/SingleThread)
   build and sign its iOS app: its Makefile/project configuration, signing
   team, entitlements, and any release or packaging mechanisms it uses for
   distribution?

6. How does the SingleThread reference app (at /Users/vardy/dev/SingleThread)
   build and sign its iOS app: its Makefile/project configuration, signing
   team, entitlements, and any release or packaging mechanisms it uses for
   distribution?

7. What does Apple document about how App Store Connect receives beta
   builds for TestFlight distribution? Cover the build mechanisms (cloud
   build vs uploaded prebuilt artifacts), accepted artifact formats,
   signing/provisioning requirements, and the API or CLI surface for
   uploading builds and managing testers.

## Notes

- Questions 1-5 are answered from the CheckStitch worktree at
  /Users/vardy/dev/alanvardy-var-993-get-a-build-working-on-testflight
  (main checkout: /Users/vardy/dev/CheckStitch).
- Question 6 is answered from /Users/vardy/dev/SingleThread.
- Question 7 is answered from Apple's public documentation via web
  research.
- All answers must describe what exists; no suggestions, no solutions.