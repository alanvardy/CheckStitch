# Structure Outline

## Approach

Ship an iOS widget extension that reads the existing App Group payload and runs a
checklist through the one live reminder path (`ChecklistReminders` →
`EventKitReminderDestination` → `RunChecklistIntent`). Because extensions cannot
link the app target, Phase 0 is the one genuinely horizontal step: move the run
seam into `CheckStitchCore`. Every later phase is a thin vertical slice: a real
WidgetKit entry point → real Core logic → the App Group store → a rendered,
tappable widget, tested and gated when it lands.

> **Design gap resolved here.** `ChecklistEntityQuery` (moving to Core) and the
> widget timeline both need to read checklists; the read model is
> `ChecklistStore`, which the design's Decision 6 list omitted. Phase 0 therefore
> also moves `ChecklistStore` + `ChecklistMerge` (pure, Swift-only deps) so the
> existing query implementation survives unchanged. If that churn explodes, fall
> back to a narrow `ChecklistReading` protocol in Core.

## Phase 0 — Core extraction (horizontal exception)

No user-visible change; the app/watch/tests keep working with `import
CheckStitchCore`. One green commit, expand-only: add the types to Core, delete
them from the app target, update consumers. Nothing new is authored.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/{AppGroup,ChecklistStore,ChecklistMerge,ChecklistReminders,EventKitReminderDestination,ChecklistEntity,RunChecklistIntent,ListChecklistsIntent}.swift`; consumers `CheckStitch/MyApp.swift`, `CheckStitch/ContentView.swift`, `CheckStitchWatch/*`, `CheckStitchTests/*`.

**Key changes** (visibility only — bodies unchanged):
- `public enum AppGroup { public static let suiteName: String; public static var defaults: UserDefaults }`
- `public final class ChecklistStore` — `init(defaults:key:textEditDelay:)` unchanged; `public var checklists: [Checklist]`, `public func checklist(id:)`
- `public enum ChecklistReminders { public static func create(from:targeting:gate:) async -> ReminderRunOutcome; public static func productionGate() async -> RunGate }`
- `public @MainActor final class EventKitReminderDestination: ReminderDestinationTargeting`
- `public struct ChecklistEntity`, `public struct RunChecklistIntent: AppIntent`, `ListChecklistsIntent`, `ChecklistEntityQuery`

**Contract**: the extension may `import CheckStitchCore` and use
`ChecklistStore(defaults: AppGroup.defaults)`, `ChecklistReminders.create(...)`,
and `RunChecklistIntent` exactly as the Siri path does.

**Tests**: existing suites unchanged (`@testable import CheckStitchCore`).
**Verify**: `make test-unit`, then `bash scripts/test.sh` green — pure move, no new tests.

---

## Phase 1 — Walking skeleton: small widget runs a checklist

User places a `systemSmall` widget; it loads the first checklist from the App
Group, shows its name, and a tap creates its reminders with no app foreground.
Green tests prove packaging (`.appex` embedded, unsigned `widget-build` leg) and
interactive-App-Intent + EventKit running out of process. Configuration is
deliberately hard-coded.

**Files**: `CheckStitchWidget/{ChecklistWidgetBundle,SingleChecklistWidget}.swift`, `CheckStitchWidget/CheckStitchWidget.entitlements`; `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidgetDisplayModel.swift`; `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift`; `project.pbxproj` (new `PBXNativeTarget` + Embed Foundation Extensions phase); `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitchWidget.xcscheme`; `Makefile` (`widget-build`), `scripts/test.sh`, `scripts/tests/run.sh` (`WARNINGS_AS_ERRORS_LEGS` + pin).

**Key changes**:
- `struct ChecklistWidgetRow: Identifiable, Equatable, Sendable { id: Checklist.ID; name: String; entityID: ChecklistEntity.ID; isRunnable: Bool; needsAccess: Bool }`
- `enum ChecklistWidgetAccessState { ready, needsAccess, needsPurchase }`
- `struct ChecklistWidgetDisplayModel { init(checklists: [Checklist], configuration: [ChecklistEntity], access: ChecklistWidgetAccessState); var rows: [ChecklistWidgetRow] }`
- `struct SingleChecklistWidget: Widget` — `StaticConfiguration`, first-checklist timeline, `Button(intent: RunChecklistIntent(checklist:))`
- `make widget-build` — extension for `generic/platform=iOS Simulator`, unsigned, `WARNINGS_AS_ERRORS`

**Contract**: the display-model API above; widget kind id; extension bundle id
`app.alanvardy.CheckStitch.widget`; run buttons always go through
`RunChecklistIntent`.

**Tests**: `ChecklistWidgetDisplayModelTests` — a checklist maps to a runnable row; empty checklists → empty rows.
**Verify**: `make test-unit` and `make widget-build` pass; manual on simulator — place widget, tap run, reminders appear without foregrounding.

---

## Phase 2 — Choose which checklist (small widget config)

User picks the checklist in the widget's edit UI instead of getting the first one.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistConfigurationIntent.swift`; `CheckStitchWidget/SingleChecklistWidget.swift`; `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift`; extension `Localizable.xcstrings`.

**Key changes**:
- `struct ChecklistConfigurationIntent: WidgetConfigurationIntent { @Parameter(title:) var checklist: ChecklistEntity?; var title/description }`
- `SingleChecklistWidget` switches `StaticConfiguration` → `AppIntentConfiguration(intent:provider:)`
- display model resolves the selected entity id to its checklist.

**Contract**: `ChecklistConfigurationIntent` + `AppIntentConfiguration` usage;
later slices attach their own configuration intents without touching this one.

**Tests**: selected entity maps to its row; unset/ghost entity → empty rows.
**Verify**: `make test-unit`, `make widget-build`; manual — edit widget, pick a checklist, it renders and runs.

---

## Phase 3 — Large widget with per-row run buttons

User places a `systemLarge` widget, picks several checklists, and each row runs
independently (one gate slot per tap).

**Files**: `CheckStitchCore/Sources/CheckStitchCore/{MultiChecklistConfigurationIntent,ChecklistWidgetDisplayModel}.swift`; `CheckStitchWidget/{ChecklistWidgetBundle,MultiChecklistWidget}.swift`; `CheckStitchTests/ChecklistWidgetDisplayModelTests.swift`.

**Key changes**:
- `struct MultiChecklistConfigurationIntent: WidgetConfigurationIntent { @Parameter(title:) var checklists: [ChecklistEntity] }`
- `struct MultiChecklistWidget: Widget` — `systemLarge`, `ForEach(model.rows)` with a per-row `Button(intent: RunChecklistIntent(checklist:))`
- display model preserves configuration order and caps to a row budget.

**Contract**: `MultiChecklistConfigurationIntent`; row `entityID` remains the
single per-row run key.

**Tests**: N entities → N ordered runnable rows; subset of configured entities missing from the store is dropped.
**Verify**: `make test-unit`, `make widget-build`; manual — large widget, three rows, each tap creates only that checklist's reminders.

---

## Phase 4 — Access and purchase states

When Reminders access is not `.fullAccess` (or a run needs the app), the widget
renders a non-interactive "open app to enable" state whose `widgetURL` launches
CheckStitch — the interactive button never shows the intent's dialog.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistWidgetDisplayModel.swift`; `CheckStitchWidget/{SingleChecklistWidget,MultiChecklistWidget}.swift`; extension `Localizable.xcstrings`; `CheckStitchTests/{ChecklistWidgetDisplayModelTests,LocalizationFixtures}.swift`.

**Key changes**:
- provider folds `EventKitReminderDestination.shared.accessStatus()` and purchase state into `ChecklistWidgetAccessState`
- display model: `access != .ready` ⇒ every row `isRunnable = false`, `needsAccess = true`
- views: runnable → `Button`, otherwise row + `widgetURL(URL(string:"checkstitch://"))`

**Contract**: `ChecklistWidgetAccessState` is the only channel for permission
state; views never call EventKit.

**Tests**: `.needsAccess` / `.needsPurchase` ⇒ no rows runnable; `.ready` ⇒ runnable.
**Verify**: `make test-unit`, `make widget-build`; manual — revoke Reminders access, widget shows the enable state and tapping opens the app.

---

## Phase 5 — Hardening, empty states, localization

Unconfigured/empty widgets, timeline refresh policy, widget-gallery metadata and
previews, and complete localization so the gate's l10n and shellcheck legs stay
green.

**Files**: `CheckStitchWidget/*` (empty-state view, gallery metadata, previews); extension `Localizable.xcstrings`; `CheckStitchTests/LocalizationFixtures.swift`; `scripts/tests/run.sh` (final pin).

**Key changes**: `TimelineReloadPolicy`/`.after` refresh; `noChecklists` empty
state; widget display name + description keys in all 6 languages.

**Contract**: none new — the display model's row/state shape is frozen.

**Tests**: `LocalizationFixtures.requiredKeys` includes every new key; empty-config path covered.
**Verify**: `scripts/l10n-check.sh`, `shellcheck scripts/*.sh scripts/tests/*.sh`, then full `./scripts/test.sh` (`gate: ok`).

---

## Testing Checkpoints

- After Phase 0: `make test-unit` + `bash scripts/test.sh` green (pure move).
- After Phase 1: `make test-unit`, `make widget-build`; manual small-widget run creates reminders.
- After Phase 2: `make test-unit`, `make widget-build`; picked checklist renders and runs.
- After Phase 3: manual large-widget per-row runs; `make widget-build`.
- After Phase 4: revoked-access manual check; display-model state tests green.
- After Phase 5: `scripts/l10n-check.sh`, `shellcheck`, full `./scripts/test.sh` prints `gate: ok`.

Next: run `!1` to plan.
