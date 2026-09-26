# Design Discussion

Ticket: VAR-1065 — home-screen widgets for CheckStitch. Repo root:
`/Users/vardy/dev/CheckStitch`; refs below are relative to it.

## Current State

- **Domain + store.** `ChecklistStore` is an `@Observable final class` in the
  *app target* (`CheckStitch/ChecklistStore.swift:3`), storage = one App-Group
  `UserDefaults` key `checklists.v1` holding a versioned `ChecklistEnvelope`
  (`:104-111`). No singleton: `MyApp.init()` owns one instance in `@State` and
  injects it (`MyApp.swift:34-46`, `ContentView.swift:632-643`). Out-of-app
  callers construct `ChecklistStore(defaults: AppGroup.defaults)` fresh per
  call (`RunChecklistIntent.swift:42`, `ChecklistEntity.swift:28-31`).
- **Run chain.** The only live path that materialises reminders is
  `ChecklistReminders.create(from:targeting:gate:)` (`ChecklistReminders.swift:28-67`):
  `gate.reserveRun()` → access → list snapshot → per-item `targeting.create` →
  release the slot unless something was created. `RunGate` /
  `RunCounter(freeRunLimit: 20)` are already in **Core**
  (`CheckStitchCore/.../RunCounter.swift:51,66,71-92`).
  `EventKitReminderDestination.shared` is `@MainActor`, holds a long-lived
  `EKEventStore` (`EventKitReminderDestination.swift:10-11`).
- **Out-of-app precedent.** `RunChecklistIntent` already runs a checklist with
  `openAppWhenRun=false` (`RunChecklistIntent.swift:17`): fresh store, shared
  destination, **status-only** EventKit pre-check (never prompts from a cold
  process, `:53-64`), gate via `ChecklistReminders.productionGate()`, outcome →
  dialog (`:66-69`). `ChecklistEntity` is keyed by `Checklist.id.uuidString`
  (rename-proof, `ChecklistEntity.swift:3-6,16-17`); `ChecklistEntityQuery`
  reads the store `@MainActor` (`:26-52`).
- **No widget surface exists.** No `.appex`, no widget target, no
  `WidgetBundle`; the only two intents are run/list. The App Group entitlement
  `group.app.alanvardy.CheckStitch` is already on the app
  (`CheckStitch/AppGroup.entitlements`), which is exactly the bridge a widget
  extension needs to read `checklists.v1`.
- **Build.** iOS 18.7 / macOS 27.0 / watchOS 26.0, Swift 6
  (`pbxproj:422,487,541`) — interactive widgets (iOS 17+) are available. The
  gate is `./scripts/test.sh`; every compiling Swift leg carries
  `WARNINGS_AS_ERRORS` (`Makefile:20`, `scripts/tests/run.sh:395`). New Swift
  files need no pbxproj edit, but a new **target** does.
- **Gap.** Widget extensions cannot link the app target. The reusable run
  chain (`ChecklistReminders`, `EventKitReminderDestination`, `AppGroup`) and
  the read model live in the app target today, so the extension cannot import
  them as-is.

## Desired End State

A new iOS **widget extension** target ships two home-screen widgets:

1. **Small (`systemSmall`)** — one checklist (chosen in the widget's edit UI)
   with a single run button.
2. **Large (`systemLarge`)** — several checklists (chosen in the edit UI), each
   row with its own run button.

Tapping a run button creates the checklist's reminders **without opening the
app**, reusing `RunChecklistIntent` semantics. When Reminders access is not
`.fullAccess`, the widget renders a non-interactive "open app to enable" state
whose `widgetURL` launches CheckStitch.

Verification of "correct":
- `make widget-build` compiles the extension with warnings-as-errors in the
  gate; the display-model suite runs in `make test-unit` (macOS).
- On a simulator/device: place each widget, pick checklists in the edit UI,
  tap a button, and confirm reminders appear in the CheckStitch Reminders list
  with no app foregrounding.
- With Reminders access revoked, the widget shows the enable state and tapping
  it opens the app.

## Patterns to Follow

- **One run primitive.** Never write a new reminder-creation path; every
  widget button routes to `ChecklistReminders.create(...)`
  (`ChecklistReminders.swift:28-67`) through `RunChecklistIntent`, preserving
  the run gate and the `ReminderRunOutcome` mapping (`:48-86`).
- **Fresh store per cold call.** `ChecklistStore(defaults: AppGroup.defaults)`
  per invocation (`RunChecklistIntent.swift:42`) — do not introduce a
  singleton for the widget.
- **Cold-process no-prompt rule.** Status-only `accessStatus()` pre-check
  (`RunChecklistIntent.swift:53-54`, `EventKitReminderDestination.swift:24-30`);
  the widget view, not the intent, surfaces the denied state.
- **`@MainActor` everywhere the run chain touches.** The run VM, destination,
  `RunCounter` and intents are all `@MainActor`; the widget display model must
  be too, or hand off explicitly.
- **Reuse the entity model.** Bind widget configuration to `ChecklistEntity`
  and `ChecklistEntityQuery` (`ChecklistEntity.swift:16-52`) rather than a new
  identifier type — names stay rename-proof (doc `:3-6`).
- **Injectable seams + fakes.** Follow the intent's `init(store:targeting:gate:)`
  (`RunChecklistIntent.swift:34-37`) and `SpyReminderDestination`
  (`CheckStitchTests/TestFixtures.swift`) so the new logic is testable without
  EventKit.
- **Gate citizenship.** New compiling legs carry `WARNINGS_AS_ERRORS`, join
  `scripts/tests/run.sh:395`, pass `shellcheck`, and never leave a bare
  `name=` destination.
- **Patterns NOT to follow:** the legacy `ChecklistCreator` +
  `EventKitReminderCreator` path (per-item, no list targeting, no run gate, no
  caller in the live flow — `ChecklistCreator.swift:29-33`); and putting
  decision logic inside the extension target (untestable in the gate).

## Design Decisions

1. **Interactive `Button(intent:)`, not `widgetURL`, for the run action.**
   Tapping runs `RunChecklistIntent` in the extension process
   (`openAppWhenRun=false`, `RunChecklistIntent.swift:17`), satisfying
   "without opening the app." `widgetURL` is reserved for the denied/unavailable
   state only.
2. **Permission denial is a widget-rendered state, not an intent dialog.**
   The display model exposes `.ready` vs `.needsAccess` from
   `accessStatus()`; interactive widget buttons cannot show the intent's dialog,
   and the Siri precedent forbids prompting from a cold process
   (`RunChecklistIntent.swift:53-54`). `.needsAccess` renders a disabled row
   with `widgetURL` → app.
3. **Large widget = per-checklist run buttons; no "Run All".** Each row maps to
   one `RunChecklistIntent`, so the run gate accounts one slot per tap and a
   `purchaseRequired` outcome is attributable to one checklist. A "Run All"
   would consume N slots and partially fail at `freeRunLimit = 20`
   (`RunCounter.swift:51`) — deferred (scope).
4. **`AppIntentConfiguration` with two widget kinds.** `SingleChecklistWidget`
   (`systemSmall`, one `ChecklistEntity`) and `MultiChecklistWidget`
   (`systemLarge`, `[ChecklistEntity]`), both via `WidgetConfigurationIntent`
   and `ChecklistEntityQuery`. Reuses the existing entity picker; the user
   chooses which checklists appear.
5. **iOS-only extension.** `systemSmall`/`systemLarge` on the iPhone/iPad home
   screen matches "home-screen widgets"; macOS/watch widgets are out of scope
   and would add a second signed slice to a provisioning-free gate.
6. **Extract the shared run seam into `CheckStitchCore`; extension is a thin
   shell.** The widget extension links the local SPM package, so the pieces it
   needs must live there: move `ChecklistReminders`,
   `EventKitReminderDestination`, `AppGroup` (and the run/list intents and
   `ChecklistEntity`) from the app target into `CheckStitchCore`, leaving the
   app target as the thin consumer. The extension target then contains only
   WidgetKit/SwiftUI views plus a `ChecklistWidgetDisplayModel` (also in Core)
   with all naming/state/button-mapping logic.
7. **Display logic is pure and testable.** `ChecklistWidgetDisplayModel` takes
   `(checklists, configuration, accessStatus)` and returns rows (`id`, `name`,
   `isRunnable`, `needsAccess`). Tested macOS-hosted with Swift Testing in
   `CheckStitchTests/`, per the existing suite conventions; no EventKit needed.
8. **New build leg + gate leg, following `watch-build`.** Add `make
   widget-build` (extension for `generic/platform=iOS Simulator`, unsigned,
   warnings-as-errors) modelled on `Makefile:78-89`, a committed shared scheme
   for the extension, a line in `scripts/test.sh`, and the leg in
   `WARNINGS_AS_ERRORS_LEGS` (`scripts/tests/run.sh:395`).
9. **App Group entitlement on both targets.** The extension reads
   `checklists.v1` from `UserDefaults(suiteName: "group.app.alanvardy.CheckStitch")`
   and the widget's App ID is prefixed by `app.alanvardy.CheckStitch`
   (`CheckStitch/AppGroup.entitlements`, `AppGroup.swift:6-11`). No KVS
   ubiquity entitlement is needed in the extension — it reads the App Group
   store, not iCloud.
10. **User-facing widget strings are localizable.** Any new string (widget
    display name, description, "open app" copy) goes through
    `Localizable.xcstrings` with all 6 languages and a
    `LocalizationFixtures.requiredKeys` entry; run `scripts/l10n-check.sh`
    first.

## What We're NOT Doing

- **No "Run All" / multi-run-in-one-tap.** Per-row buttons only.
- **No macOS, watchOS, visionOS, or CarPlay widget surfaces.**
- **No Lock Screen / accessory widgets, complications, or Live Activities.**
- **No Control Center / macOS 26 `ControlWidget`.**
- **No new persistence or sync path.** The widget reads the existing App Group
  payload read-only and never writes checklists.
- **No in-app widget-configuration screen** (`Option C` in Q3 rejected); config
  stays in the widget's own edit UI.
- **No editing, deleting, or completing reminders from the widget** — CheckStitch
  stays create-only.
- **No change to the legacy `ChecklistCreator` path** or to the intents'
  behaviour beyond the file move required by Decision 6.
- **No App Store / marketing asset work** in this ticket.

## Open Risks

- **The `.appex` target is unverified on this machine.** Producing a second
  distributable (own App ID, provisioning profile, App Group membership, and
  signing) for a real device is unproven here; the simulator + unsigned
  `widget-build` leg is the safe gate, and device placement is a manual check.
- **EventKit from a widget-extension process.** The Siri intent precedent says
  it works, but the widget's interactive-intent time budget is tight; a slow
  EventKit snapshot may be cut short. If it proves flaky, fall back to
  `widgetURL` for the run action (Decision 1) — a contained change.
- **Decision 6 is a cross-cutting refactor.** Moving `ChecklistStore`'s
  neighbours (`ChecklistReminders`, `EventKitReminderDestination`, `AppGroup`,
  intents/entity) into Core touches app, watch, tests, and the Makefile; the
  low-risk alternative is per-target source membership
  (`PBXFileSystemSynchronizedBuildFileExceptionSet`), which avoids the move but
  duplicates compilation. Prefer the Core move; revisit if churn explodes.
- **Widget configuration multi-select.** `[ChecklistEntity]` parameters and
  small-vs-large kind split need SDK verification via compile (`swiftui-sdk`
  skill); the exact `WidgetConfigurationIntent` shape is not confirmed by the
  research.
- **Localization coverage** adds a per-language pass; missing keys will trip
  `scripts/l10n-check.sh` and the gate.
- **Purchase gating from the widget.** A `purchaseRequired` outcome cannot open
  the paywall from a widget; the widget should show that the run needs the app.
  Exact copy is a design detail for planning.