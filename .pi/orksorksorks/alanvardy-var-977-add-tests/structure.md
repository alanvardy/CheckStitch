# Structure Outline

## Approach

Bottom-up: stand up the test harness first (local `CheckStitchCore` package + app-hosted
`CheckStitchTests` target), then move pure logic into it layer by layer — each layer ships
with green Swift Testing suites before the next is touched. The EventKit seam is stubbed
first so the creator/view-model behaviour is testable without permissions, then the views
are rewired onto the tested core, and only then does the gate and the single XCTest UI
smoke come online. No code lands without its tests.

> **Cross-cutting caveat.** `project.pbxproj` target/scheme wiring (§1) is not a logic
> layer and cannot be validated by unit tests — it is proven by `xcodebuild -list`,
> a placeholder test, and `make build`. All other layers are genuinely horizontal.

---

## Stage 1: Test Harness Scaffolding

Delivers the local package, the macOS-hosted unit target, and the scheme `TestAction` so
every later stage has somewhere to land. Green placeholder test proves the runner works
(unsigned, macOS, Swift Testing) before any logic moves.

**Files**: `CheckStitchCore/Package.swift` (new, sources only, no `Tests/`),
`CheckStitchCore/Sources/CheckStitchCore/Placeholder.swift` (new, temporary),
`CheckStitchTests/SmokeTests.swift` (new), `CheckStitch.xcodeproj/project.pbxproj`
(`XCLocalSwiftPackageReference`, `CheckStitchTests` native target + `.xctest` product),
`CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme` (new, `TestAction`,
`shouldAutocreateTestPlan="YES"`).

**Key changes**:
- `Package.swift` — tools 6.0; `.iOS("18.7")`, `.macOS("27.0")`; one library product
  `CheckStitchCore`; package-level `swiftSettings` MainActor-isolation if supported
  (design Risk 2; fall back to explicit `@MainActor`).
- `struct SmokeTests` — one `@Test func harnessRuns()`; no `test` prefix.
- pbxproj: `PBXFileSystemSynchronizedRootGroup` for `CheckStitchTests/` (mirrors
  `SingleThread/project.pbxproj:110-117`).

**Tests**: `harnessRuns()` (proves the target executes and `@testable import CheckStitchCore` resolves).
**Verify**: `xcodebuild -list -project CheckStitch.xcodeproj` shows all three targets;
`bash -c 'cd CheckStitchCore && swift build'` succeeds;
`xcodebuild -scheme CheckStitch -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` is green; `make build` unchanged.

---

## Stage 2: Pure Models

Moves the three isolation-free value types into the package and deletes them from the app,
proving the app still compiles on package types. Pure, so no EventKit/MainActor needed.

**Files**: `Sources/CheckStitchCore/ChecklistItem.swift`, `ChecklistWidth.swift`,
`AppearanceMode.swift`; remove those definitions from `CheckStitch/ContentView.swift`,
`CheckStitch/AppearanceMode.swift`; tests `CheckStitchTests/TestFixtures.swift` (new:
`makeItem(_:)`), `ChecklistItemTests.swift`, `ChecklistWidthTests.swift`,
`AppearanceModeTests.swift`, `AppearanceModePreferenceTests.swift`.

**Key changes**:
- `struct ChecklistItem: Identifiable, Equatable { let id: UUID; var title: String }`
- `enum ChecklistWidth { nonisolated static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat }`
- `enum AppearanceMode: String, CaseIterable { case system, light, dark }` with
  `windowOverrideStyle` (iOS), `appKitAppearance` (macOS), `colorScheme`, `systemImage`,
  `title`, `static func load(from defaults: UserDefaults = .standard) -> Self`
- `struct AppearanceModePreference { static let defaultsKey; var rawValue: String; func setRawValue(_:) }`
- `func makeIsolatedDefaults() -> UserDefaults` — `suiteName:` + `removePersistentDomain`.
- `ContentView`/`SettingsView` `@AppStorage(AppearanceModePreference.defaultsKey)` instead
  of the `"appearanceMode"` literal.

**Tests**: `maxContentWidthScalesBelowCeiling`/`…ClampsAtCeiling` (happy + boundary),
`checklistItemStableIdentityForDuplicateTitles`, `appearanceModeLoadsValidRawValue` /
`invalidRawValueFallsBackToSystem` (sad), `preferenceSetThenReadRoundTrips` /
`preferenceIgnoresUnknownStoredValue` (sad). Parametrize `[nil, "", " ", "\n"]`, `[".light", "dark", "bogus"]` via `@Test(arguments:)`.
**Verify**: same macOS `-only-testing:CheckStitchTests` run green; `make build` green.

---

## Stage 3: EventKit Seam (protocol + real adapter + spy)

The injection boundary: permission and reminder creation behind one protocol, with a real
`EKEventStore`-backed adapter and an in-memory spy. No business decisions live here.

**Files**: `Sources/CheckStitchCore/ReminderCreating.swift`; tests `SpyReminderCreator`
(added to `TestFixtures.swift`) and `EventKitReminderCreatorTests.swift`.

**Key changes**:
- `protocol ReminderCreating: Sendable { func requestAccess() async throws -> Bool; func create(title: String) async throws }`
- `final class EventKitReminderCreator: ReminderCreating { init(eventStore: EKEventStore) }` — one long-lived store (design; never the `EKEventStore()`-per-call anti-pattern).
- `final class SpyReminderCreator: ReminderCreating, @unchecked Sendable` — `accessGranted`, `accessError`, `createError`, recorded `createdTitles`.

**Tests**: `creatorRequestsAccessBeforeCreating`, `spyRecordsCreatedTitlesInOrder`,
`creatorSurfacesThrownAccessError` (sad). Fixture uses `@MainActor sharedTestEventStore`
kept alive globally (design Risk 7).
**Verify**: macOS unit run green; `@MainActor` suites compile without test-target MainActor defaulting.

---

## Stage 4: ChecklistCreator (business logic)

Owns the whole reminder-creation policy: ask permission, filter blanks, create one reminder
per item, and return a typed outcome instead of silently `return`ing.

**Files**: `Sources/CheckStitchCore/ChecklistCreator.swift`; tests `ChecklistCreatorTests.swift`.

**Key changes**:
- `enum ChecklistCreationOutcome: Equatable { case created(count: Int); case permissionDenied; case failed(String) }`
- `struct ChecklistCreator { init(reminders: ReminderCreating); func create(from items: [ChecklistItem]) async -> ChecklistCreationOutcome }`
- `extension ChecklistItem { var isBlank: Bool }` — trims whitespace/newlines.

**Tests**: `createSkipsBlankTitles` parametrized over `[nil, "", "   ", "\n\n", "t", "t "]`
(mirrors `SingleThreadTests/ReminderSkipTests.swift:108`), `createReturnsCountForNonBlankItems`,
`permissionDeniedReturnsOutcomeWithoutCreating` (sad), `createStopsAndReportsFailureWhenSaveThrows` (sad),
`allBlankItemsCreateNothing`.
**Verify**: macOS unit run green.

---

## Stage 5: Environment + ChecklistViewModel

Adds the small DI container and the `@Observable` view model that drives the UI, so state
transitions and the spinner/created flags become unit-testable.

**Files**: `Sources/CheckStitchCore/Environment.swift`, `ChecklistViewModel.swift`;
tests `ChecklistViewModelTests.swift`.

**Key changes**:
- `struct Environment { let reminderCreator: ReminderCreating }`
- `@Observable @MainActor final class ChecklistViewModel { var items: [ChecklistItem]; var checklistName: String; var isCreatingChecklist: Bool; var isChecklistCreated: Bool; init(environment: Environment); func createChecklist() async }` — calls `ChecklistCreator`, maps outcome to flags.

**Tests**: `createChecklistSetsCreatedFlagOnSuccess` (happy), `createChecklistTogglesSpinnerAroundWork`,
`permissionDeniedLeavesCreatedFlagFalse` (sad), `failedCreationLeavesCreatedFlagFalse` (sad),
`viewModelStartsWithSeededItems`.
**Verify**: macOS unit run green.

---

## Stage 6: App Rewiring (presentational layer)

Thins the app target: views render from `ChecklistViewModel`, pull `Environment` from the
app entry point, and `AppDelegate`/`MacAppDelegate` keep only platform window styling.

**Files**: `CheckStitch/ContentView.swift`, `CheckStitch/MyApp.swift`,
`CheckStitch/AppDelegate.swift`, `CheckStitch/SettingsView.swift` (imports
`CheckStitchCore`); tests `CheckStitchTests/ViewRenderTests.swift`.

**Key changes**:
- `ContentView` owns `@State private var viewModel: ChecklistViewModel`; `AppDelegate`/
  `MacAppDelegate` call the package's `AppearanceMode` / `AppearanceModePreference`; remove
  moved definitions. `#if os(iOS)` branches stay in the app.

**Tests**: `contentViewBodyEvaluates`, `settingsViewListsAllAppearanceModes` — Swift Testing
render smoke, view-model backed (no accessibility sweep; that is Stage 7).
**Verify**: macOS unit run green; `make build` green; manual `make run` on the worktree sim
shows identical behaviour.

---

## Stage 7: UI Smoke Target + Gate

Adds the single XCTest UI case and makes the repo gate own the tests.

**Files**: `CheckStitchUITests/CheckStitchUITests.swift` (new), pbxproj + scheme
`TestAction` for `CheckStitchUITests`, `Makefile` (`test` target), `scripts/test.sh`.

**Key changes**:
- `final class CheckStitchUITests: XCTestCase` — one launch + `performAccessibilityAudit`
  case on the worktree `.simulator_id` (never a bare `name=`).
- `make test` — macOS `-only-testing:CheckStitchTests` (`CODE_SIGNING_ALLOWED=NO`) then
  `build-for-testing` → `test-without-building -only-testing:CheckStitchUITests` on `$(SIM)`.
- `scripts/test.sh` — `make build` → `make test` → `shellcheck scripts/*.sh`, keep `gate: ok`.

**Tests**: the one UI smoke case (launch + audit).
**Verify**: `bash scripts/test.sh` prints `gate: ok`; `make test` runs both targets green;
`bash scripts/run-devices.sh` untouched.

---

## Stage 8: Documentation Contract

Updates the standing instructions so the new layout and gate are discoverable.

**Files**: `AGENTS.md` (repo root), `linear-project.md` untouched.

**Key changes**: replace "no test target — the gate is `./scripts/test.sh`" with the new
gate (build + unit + UI smoke + shellcheck); document `make test`, where tests live, and the
macOS-vs-simulator destination rule; replace "one app target, no dependencies" in Layout.

**Tests**: none (docs). **Verify**: `./scripts/test.sh` still green after the edit.

---

## Testing Checkpoints

- After Stage 1: `xcodebuild -list` shows 3 targets, placeholder test green, `swift build` green, `make build` green.
- After Stage 2: `ChecklistItem*`/`ChecklistWidth*`/`AppearanceMode*` suites green; app compiles on package types.
- After Stage 3: seam + spy suites green; one long-lived `sharedTestEventStore` fixture in place.
- After Stage 4: blank-filter/denial/failure outcomes green — this is the behaviour core; nothing above may proceed if red.
- After Stage 5: view-model flag transitions green.
- After Stage 6: render smokes green, manual `make run` unchanged.
- After Stage 7: `scripts/test.sh` prints `gate: ok` (build + unit + UI + shellcheck).
- After Stage 8: gate still green; AGENTS.md contract matches reality.