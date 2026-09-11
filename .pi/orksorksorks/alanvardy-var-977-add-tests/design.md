# Design Discussion

Ticket: VAR-977 — add a test suite to CheckStitch.
Decisions locked with the user: 1B (local Swift package) + Q6-A (package sources,
app-hosted test target) + 2C (MVVM/service/DI) + 3A (macOS host) + 4A (gate) + 5B (one UI smoke).

## Current State

CheckStitch is a single app target with **zero test infrastructure**:

- App source, 5 files under `CheckStitch/` (`ContentView.swift`, `SettingsView.swift`,
  `AppearanceMode.swift`, `AppDelegate.swift`, `MyApp.swift`), all auto-synced by
  `PBXFileSystemSynchronizedRootGroup` (`project.pbxproj:13-19`) — new *files* need no
  pbxproj edit, but a new *target* does.
- Gate is `scripts/test.sh` = `make build` + `shellcheck scripts/*.sh`, printing
  `gate: ok` (`scripts/test.sh:9-14`). `Makefile` has `build`/`run`/`clean` only
  (`Makefile:14-23`); destination precedence is explicit `SIM=` > `.simulator_id` >
  shared default (`Makefile:2-6`).
- The reminder flow is inline in the view: `createChecklistReminders() async`
  builds a fresh `EKEventStore()` per call (`ContentView.swift:121`), requests
  `requestFullAccessToReminders()` and silently returns on denial (`:123-124`), then
  per non-blank item constructs `EKReminder(eventStore:)` and
  `try eventStore.save(reminder, commit: true)` (`:126-133`).
- Only pure, isolatable logic today: `ChecklistWidth.maxContentWidth` (`:147-150`),
  `ChecklistItem` (`:155-158`), the `AppearanceMode` enum mappings, and
  `AppearanceModePreference` (`AppearanceMode.swift:16-113`). Everything else is
  `@State`/`@Binding` SwiftUI.
- Reference app `/Users/vardy/dev/SingleThread` is the pattern source: a
  `SingleThreadCore` local package (`SingleThreadCore/Package.swift`, tools 6.0,
  platforms iOS 18.7 / watchOS 26.5 / macOS 26.5), **sources only — no `Tests/`**,
  linked via `XCLocalSwiftPackageReference` (`SingleThread.xcodeproj/project.pbxproj:459, 1228`)
  and tested by the app-hosted `SingleThreadTests` target with
  `@testable import SingleThreadCore` (`SingleThreadTests/ReminderDictationParserTests.swift:3`).

## Desired End State

```
CheckStitchCore/                      # new local SPM package, sources only
  Package.swift                       # tools 6.0; .iOS("18.7") .macOS("27.0")
  Sources/CheckStitchCore/
    ChecklistItem.swift               # model (from ContentView.swift:155-158)
    ChecklistWidth.swift              # pure math (from :147-150)
    ReminderCreating.swift            # protocol seam + EventKitReminderCreator
    ChecklistCreator.swift            # permission + blank filter + per-item loop
    ChecklistViewModel.swift          # @Observable state, items, name, spinner flags
    AppearanceMode.swift              # enum + mappings + AppearanceModePreference
    Environment.swift                 # small DI container
CheckStitchTests/                     # new app-hosted target, macOS host, Swift Testing
  TestFixtures.swift
  ChecklistWidthTests.swift
  ChecklistItemTests.swift
  ChecklistCreatorTests.swift
  ChecklistViewModelTests.swift
  AppearanceModeTests.swift
  AppearanceModePreferenceTests.swift
CheckStitchUITests/                   # new app-hosted target, iOS sim, XCTest
  CheckStitchUITests.swift            # one launch + accessibility smoke test
CheckStitch/                          # app target — thin, views + delegates only
```

Verify it works when:

- `bash -c 'cd CheckStitchCore && swift build'` succeeds (package compiles standalone on macOS).
- `make test` runs `CheckStitchTests` on `platform=macOS` with `CODE_SIGNING_ALLOWED=NO`
  and `CheckStitchUITests` on this worktree's `.simulator_id` simulator, both green.
- `bash scripts/test.sh` runs build + unit tests + UI smoke + shellcheck and prints `gate: ok`.
- `make build` still succeeds unchanged, and the app behaves identically by hand.

## Patterns to Follow

1. **Framework split is strict** — Swift Testing (`import Testing`, `@Test`, `#expect`,
   `try #require`) in the unit target; XCTest only in the UI target
   (`SingleThreadUITests/SingleThreadUITests.swift` is the only XCTest importer; `conventions.md`).
2. **Suite shape** — `struct <Thing>Tests` named after the file; `@MainActor` on suites
   that touch EventKit or main-actor state; `@Suite(.serialized)` for shared-state suites
   (all 30 `@Suite(` uses in SingleThread are serialized — no bare `@Suite`).
3. **Test names are behavior sentences, never `test`-prefixed** (SwiftFormat
   `preferSwiftTesting` strips the prefix): `func maxContentWidthScalesBelowCeiling()`
   (`SingleThreadTests/CardWidthTests.swift:7`).
4. **Parametrize with `@Test(arguments: [...])`** over literal arrays — e.g. the blank-title
   cases `[nil, "", "   ", "\n\n", "t", "t "]` (`SingleThreadTests/ReminderSkipTests.swift:108`).
5. **Fixtures** — one shared `TestFixtures.swift`; a global `@MainActor` EventStore
   (`SingleThreadTests/TestFixtures.swift:11`) that must outlive reminders because
   `EKReminder` holds a weak store reference (`:6-9`); builders construct but never save
   (`makeReminder` `:16-35`).
6. **EventKit seam via protocol + in-memory double** — mirror `EventKitStoring.swift` /
   `InMemoryEventStore.swift` in `SingleThreadCore/Sources/`.
7. **Actor isolation** — package/app targets run `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
   (`project.pbxproj:284`); **test targets do not**, so tests opt in per-suite; pure math
   escapes isolation via `nonisolated` (`ContentView.swift:145-150`); test fakes use
   `@unchecked Sendable` under Swift 6 warnings-as-errors (`StubBundle.swift:4-7`).
8. **Destination discipline** — never a bare `name=` destination; prefer the worktree
   `.simulator_id` (`AGENTS.md:17-18`, `Makefile:5-6`).
9. **Local package wiring** — `XCLocalSwiftPackageReference` + a product dependency per
   consuming target (`SingleThread.xcodeproj/project.pbxproj:459, 1228`). The installed
   `xcodeproj` ruby gem can script this, or hand-edit the pbxproj.
10. **Result bundles / runner** — `-resultBundlePath` + `xcrun xcresulttool get test-results
    summary` if a single-suite runner is needed (`SingleThread/scripts/test-one.sh:57`).

**Do NOT follow:** the current `EKEventStore()`-per-call pattern (`ContentView.swift:121`) —
SingleThread keeps one store alive precisely because reminders weakly reference it; the
silent `return` on permission denial (`:123-124`) — the refactor returns a typed outcome so
tests can assert it; `@AppStorage("appearanceMode")` (`ContentView.swift:18-19`) hardcoding
the same literal as `AppearanceModePreference.defaultsKey` (`AppearanceMode.swift:100-101`) —
source the string from the type.

## Design Decisions

1. **Core package, not in-target logic**: extract testable logic into
   `CheckStitchCore` as a local SPM library (tools 6.0, platforms `.iOS("18.7")`,
   `.macOS("27.0")` matching `IPHONEOS_DEPLOYMENT_TARGET`/`MACOSX_DEPLOYMENT_TARGET`,
   `project.pbxproj:173, 175`) — matches SingleThreadCore and keeps the app target thin.
   **Sources only, no `Tests/`**; the app-hosted `CheckStitchTests` target tests it via
   `@testable import CheckStitchCore` (Q6-A, `SingleThreadCore/Package.swift`).
2. **MVVM + service layer + DI container** (2C): `ChecklistViewModel` (`@Observable`) owns
   `items`, `checklistName`, `isCreatingChecklist`, `isChecklistCreated`; `ChecklistCreator`
   owns permission + filter + save loop; `ReminderCreating` is the injection seam;
   `Environment` is a *small* struct of protocols/closures, not a framework.
   Views become render-only; `ContentView` keeps only SwiftUI plumbing and `.onChange`
   appearance dispatch (`ContentView.swift:32-39`).
3. **EventKit seam**: `ReminderCreating` with `EventKitReminderCreator` (real, one long-lived
   store passed in) and an in-memory/spy double for tests. Permission asks move behind the
   same protocol so denial is testable without touching EventKit.
4. **Appearance splits by platform purity**: `AppearanceMode` enum, `colorScheme`,
   `systemImage`, `title`, and `AppearanceModePreference` move into the package;
   `UIUserInterfaceStyle`/`NSAppearance` window application (`AppDelegate.swift:13-53`)
   stays in the app. iOS-branch mappings stay `#if os(iOS)`; only the macOS branch is
   exercised by the macOS-host run.
5. **Runner = xcodebuild, destination = macOS host** (3A): unit tests via
   `xcodebuild test -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests`
   (mirrors `SingleThread/Makefile:35-36`). No sim boot, no signing, no App Group gap
   (`scripts/run-devices.sh:1-40`).
6. **Swift Testing for units, XCTest for the single UI smoke** (5B):
   `CheckStitchUITests` gets one launch + `performAccessibilityAudit` case on the worktree
   simulator via `build-for-testing` → `test-without-building -only-testing:CheckStitchUITests`.
7. **Fixtures**: `CheckStitchTests/TestFixtures.swift` holds `@MainActor sharedTestEventStore`,
   `makeItem(_:)`, `SpyReminderCreator`, and `makeIsolatedDefaults()` using
   `UserDefaults(suiteName:)` + `removePersistentDomain` so appearance tests never touch the
   real defaults.
8. **Gate owns tests immediately** (4A): add `make test`; `scripts/test.sh` becomes
   `make build` → `make test` → `shellcheck scripts/*.sh`, keeping the `gate: ok` line.
9. **AGENTS.md contract updated**: replace the "There is no test target — the gate is
   `./scripts/test.sh`" paragraph with the new gate (build + unit + UI smoke + shellcheck),
   `make test`, where tests live, and the macOS-vs-simulator destination rule. Replace
   "one app target, no dependencies" in Layout with the package + two test targets.
10. **UI smoke is one test, not a suite**: no accessibility-audit sweep, no snapshot tests.

## What We're NOT Doing

- No watch target, no `SingleThreadWatchTests` analogue, no watch UI tests.
- No CI (`.github/workflows`) — the repo has none today; gate stays local.
- No coverage/xccov/periphery/swiftlint/swiftformat targets — those are SingleThread-only
  (`conventions.md` "Gate staging"); not adding a linter in this ticket.
- No `Tests/` target inside `CheckStitchCore` and no `swift test` runner (Q6-A).
- No UI tests beyond the single launch/accessibility smoke case.
- No new app features, no redesign of the checklist UI, no persistence of checklists.
- No per-function mock library or third-party dependency; the container is hand-rolled.
- No changes to `scripts/run-devices.sh`, entitlements, signing values, or bundle id.
- No deployment-target bumps to satisfy the package.

## Open Risks

1. **2C is the largest refactor in this ticket.** Heavy MVVM + service layer + DI container
   for a ~230-line, 5-file app is more structure than the logic needs. Boundary: one
   `ChecklistViewModel`, one `ChecklistCreator`, one `Environment` struct — no mediator
   chains, no reactive plumbing beyond `@Observable`. If the plan starts sprouting
   layers, cut back to 2A.
2. **Package actor-isolation parity.** The app sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
   (`project.pbxproj:284`) but a `Package.swift` cannot inherit Xcode build settings. Verify
   whether this toolchain supports `.defaultIsolation(MainActor.self)` in `swiftSettings`; if
   not, annotate package types `@MainActor` explicitly so the app compiles unchanged.
3. **Test-target isolation**: tests must NOT get MainActor-by-default; per-suite `@MainActor`
   is the convention (`conventions.md`). A wrongly defaulted test target makes suites
   vacuously pass.
4. **iOS-only code is untested on a macOS host.** `AppDelegate.applyAppearance`'s iOS branch
   and `windowOverrideStyle` are `#if os(iOS)`; the macOS run cannot see them. Accepted,
   but keep the split so the untested surface is only window styling.
5. **pbxproj target wiring is hand-scripted.** No scheme file exists (autocreated only), and
   a new target requires editing `project.pbxproj` — adding `CheckStitchTests` and
   `CheckStitchUITests` targets, `XCLocalSwiftPackageReference`, and a shared scheme with a
   TestAction (SingleThread model: `project.pbxproj:92-117`, `SingleThread.xcscheme:39-69`).
   No `project.pbxproj` in the repo has been edited by an automated tool before, so a broken
   pbxproj is the highest-probability failure; verify `xcodebuild -list` and a clean
   `make build` before anything else.
6. **`.xctest` provenance on macOS.** `SingleThread/Makefile:35-36` proves the pattern works
   for that repo; CheckStitch's `MACOSX_DEPLOYMENT_TARGET = 27.0` matches this machine's
   macOS 27.0, but the test bundle must be signed-off correctly — `CODE_SIGNING_ALLOWED=NO`
   and `ENABLE_APP_SANDBOX` (`project.pbxproj:257`) may interact for the host app on macOS.
   If the macOS run proves non-viable, fall back to running `CheckStitchTests` on the iOS
   simulator (same destination as the UI smoke) — the only decision this would change is
   runtime, not layout.
7. **`EKReminder` weak-store lifetime** will bite the tests: any fixture that builds a
   reminder must retain `sharedTestEventStore` globally (`SingleThreadTests/TestFixtures.swift:6-11`).
