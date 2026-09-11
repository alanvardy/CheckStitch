# Research Questions

## Context

Focus areas: the Swift app source under `CheckStitch/` (the screen, appearance
settings, app entry/delegate files), the CheckStitch build and gate wiring
(Makefile, scripts/, xcodeproj, entitlements), and the reference app at
`/Users/vardy/dev/SingleThread` — its test packages, shared test fixtures,
build scripts that run test suites, and CI configuration. Both repos'
`AGENTS.md` files document conventions around the build, gate, and platform
constraints. All findings need `file:line` references.

## Questions

1. How does the checklist-to-reminders creation flow in
   `CheckStitch/ContentView.swift` work, end to end? Trace
   `createChecklistReminders()` from user input to
   `EKEventStore.save(reminder, commit: true)`: what kinds of requests and
   objects it builds (EKEvent, EKReminder), how `ChecklistItem` and
   `ChecklistWidth` are modeled and computed, and which parts of the file
   touch SwiftUI UI types (views, bindings, animations) versus pure logic.

2. How does the appearance system in CheckStitch work across platforms?
   Describe `AppearanceMode.swift`'s enum and its per-platform mappings, the
   `AppearanceModePreference` struct's UserDefaults persistence (defaultsKey,
   `load(from:)`), how `AppDelegate.swift` applies the chosen mode on iOS and
   macOS (`applyAppearance`), and where `#if os(...)` conditionals gate code.

3. How is the test suite wired into the SingleThread build, from Makefile
   targets to xcodebuild and CI? Trace the Makefile test/check/coverage
   targets, `scripts/test.sh` phases (swiftformat, swiftlint, build /
   build-for-testing, periphery scan, test-without-building, `-only-testing`,
   result bundles, `xcrun xcresulttool`), how schemes/TestActions are
   declared in the project file, how test files are discovered, and the CI
   workflow steps.

4. What concrete patterns do SingleThread's unit test files use with the
   Swift Testing framework? Show representative `@Test`/`@Suite` examples
   with imports and assertion styles, how tests are named and organized
   across SingleThreadTests and SingleThreadWatchTests, and what each suite
   covers.

5. What do SingleThread's shared test fixtures provide? Survey
   `TestFixtures.swift` and the other helper files in SingleThreadTests
   (BackgroundTestFixtures, LocalizationTestHelpers, StubBundle,
   UITestingSeedTests): what builders and fakes they define
   (`sharedTestEventStore`, `makeReminder`, `makeCalendar`, `FakeSession`),
   how they are scoped, and how they interact with EventKit and actor
   isolation.

6. What are the exact mechanics of CheckStitch's build and gate today?
   Describe `scripts/test.sh`, the Makefile targets, `.simulator_id`
   destination precedence, shellcheck usage, the xcodeproj settings
   (PBXFileSystemSynchronizedRootGroup, GENERATE_INFOPLIST_FILE,
   SWIFT_DEFAULT_ACTOR_ISOLATION, IPHONEOS_DEPLOYMENT_TARGET),
   `AppGroup.entitlements`, and the NSReminders usage-description key
   requirement mentioned in AGENTS.md, plus what macOS- vs iOS-specific
   signing or deployment constraints the scripts encode.