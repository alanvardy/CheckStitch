# Design Discussion

Goal: two App Intents over the existing reminder-creation machinery — **Run
Checklist** (creates all of a checklist's items as Reminders) and **List My
Checklists** (side-effect-free query). No intent parameters beyond the
checklist selector.

## Current State

- **Model/persistence**: `Checklist` (`id: UUID` stable and immutable across
  rename and sync, `CheckStitchCore/.../Checklist.swift:92,100`); `ChecklistStore`
  is an app-target `@Observable` over `UserDefaults` suite
  `group.app.alanvardy.CheckStitch` (`ChecklistStore.swift:20,49-53`,
  `AppGroup.swift:11-13`). Reads we need already exist: `checklists` (:20) and
  `checklist(id:)` (:101-103). Intents never need to mutate it.
- **Run path**: `ChecklistReminders.create(from:)` → `create(from:targeting:)`
  (`CheckStitch/ChecklistReminders.swift:12-40`) over the
  `ReminderDestinationTargeting` seam (`ReminderDestinationTargeting.swift:83-88`);
  permission via `requestAccess() -> Bool` (`ChecklistReminders.swift:18`,
  `EventKitReminderDestination.swift:16-18`), destination resolved **before** the
  first create (`:19-23`, zero-created `.destinationMissing`), then a per-item
  loop calling `create(title:notes:in:dueDateComponents:)` (`:25-35`).
- **Per-item mapping is already complete on this path**: `item.title`,
  `item.description` (nil when blank), `item.dueDateComponents(today:)`
  (`ChecklistItem+DueDate.swift:10-20`) and the checklist's
  `destinationListIdentifier` (`EventKitReminderDestination.swift:38-43`).
- **Outcomes**: `ReminderRunOutcome` = `.created(count)` / `.destinationMissing`
  / `.permissionDenied` / `.failed(String)`, each pre-baking
  `errorMessage` (`ReminderDestinationTargeting.swift:58-73`). A mid-loop throw
  (`ReminderDestinationError.listMissing`, `EventKitReminderDestination.swift:53-59`)
  discards the count → today **partial creation is indistinguishable from total
  failure**.
- **Consumer**: `ContentView.createReminders(for:)` (`ContentView.swift:373-395`)
  switches on the outcome; non-success sets `runErrorMessage` → "Couldn't create
  reminders" alert (`:156-163`).
- **Platform**: `@main MyApp: App` with os-gated delegate adaptors
  (`MyApp.swift:11-24`), `GENERATE_INFOPLIST_FILE = YES` (keys are
  `INFOPLIST_KEY_*` build settings + per-locale `InfoPlist.strings`), one window
  group, `NSUbiquitousKeyValueStore` sync. **No external-input surface exists**
  (no URL/notification/intent handling) — intents are the first one.
- **Tests**: `CheckStitchTests` does `@testable import CheckStitch` and
  `@testable import CheckStitchCore` (`ChecklistStoreTests.swift:1-3`), fakes in
  `TestFixtures.swift` (`SpyReminderDestination`, `makeIsolatedDefaults`), exact
  `errorMessage` assertions at `ChecklistRemindersTests.swift:165-168`.
- **Out-of-repo precedent**: `SingleThreadCore/.../ReminderIntents.swift`
  (`public struct X: AppIntent`, `isDiscoverable = false`, `@MainActor perform()`,
  fresh store per perform) and its `EKEventStore.authorizationStatus(for:)`
  pre-check — the designated Reminders/EventKit reference.

## Desired End State

**`CheckStitch/Intents/RunChecklistIntent.swift`** — `RunChecklistIntent: AppIntent`,
`title: LocalizedStringResource`, parameter `checklist: ChecklistEntity`
(`AppEntity`, selected via `ChecklistEntityQuery: EntityStringQuery` over
`store.checklists`), `static var parameterSummary`. `@MainActor perform()`:

1. read a fresh store, `guard let checklist = store.checklist(id:)` else throw a
   "checklist no longer exists" error;
2. `guard remover.accessStatus == .fullAccess`, else return a
   `.permissionDenied`-style failure with grant instructions (no prompt);
3. `await ChecklistReminders.create(from: checklist)` on the production seam;
4. map outcome → `ProvidesDialog` result: success "Created 7 reminders for
   Groceries.", missing destination "That list no longer exists; no reminders
   were created.", partial "Created 3 of 7 reminders for Groceries; the rest
   were not created (…)".

**`CheckStitch/Intents/ListChecklistsIntent.swift`** — no-parameter
`AppIntent` returning `ProvidesDialog`: "You have 3 checklists: Groceries,
Packing, Chores." / "You don't have any checklists yet.".

**`CheckStitch/Intents/CheckStitchShortcuts.swift`** — minimal
`AppShortcutsProvider` with one phrase per intent so Siri surfaces them without
manual Shortcuts setup.

Correct means: (a) unit tests drive each intent body through
`SpyReminderDestination` and assert exact dialogue text; (b) the full gate
(`bash scripts/test.sh`) passes; (c) the signed macOS build exposes both actions
in Shortcuts.app and a spoken "Run Groceries in CheckStitch" creates the
reminders in the resolved list on a real device.

## Patterns to Follow

- **Build on the production seam**, not the legacy creator: `ChecklistReminders`
  + `ReminderDestinationTargeting` (`ChecklistReminders.swift:16-40`,
  `ReminderDestinationTargeting.swift:83-88`). ⚠️ Do **not** reuse
  `ChecklistCreator`/`ReminderCreating` (`ChecklistCreator.swift:18-50`,
  `ReminderCreating.swift:9-43`) — it silently drops `notes` and ignores
  `destinationListIdentifier` (always `defaultCalendarForNewReminders()`), which
  is exactly the "nothing silently dropped" failure the task forbids.
- **Outcome enums carry their own user-facing text** (`errorMessage`,
  `ReminderDestinationTargeting.swift:66-73`; `ChecklistImportError.message`,
  `ChecklistImportSession.swift:21-27`) — partial/permission dialogue text goes
  in Core next to the other messages, not inline in the intent.
- **Errors are thrown as typed enums** with `errorDescription` when they must
  escape a `do/catch` (`EventKitReminderDestination.swift:53-59`); the intent's
  own "checklist gone" failure follows that shape.
- **Store access is read-only and injectable**: `init(defaults: key: ...)`
  (`ChecklistStore.swift:49-53`) + `AppGroup.defaults` (`AppGroup.swift:11-13`),
  mirroring `makeIsolatedDefaults` usage in tests.
- **Suites**: `struct XTests` + `@Test`/`#expect`, behaviour-named functions,
  `@MainActor` for anything touching EventKit/store/`perform()`; fakes from
  `TestFixtures.swift`. Never add `SWIFT_DEFAULT_ACTOR_ISOLATION` to test
  targets.
- **Localization contract**: every new key needs all six languages in
  `CheckStitch/Localizable.xcstrings` (`LocalizationTests.catalogsHaveAllSixLanguages`,
  `LocalizationTestHelpers.swift:58-64`) and must differ from English for
  de/es/fr/ja/zh-Hans unless added to `LocalizationFixtures.excludedIdentities`
  (`:106-120`). Add keys to `LocalizationFixtures.requiredKeys` so they cannot be
  dropped.
- **New files under `CheckStitch/` need no `project.pbxproj` edit**
  (`PBXFileSystemSynchronizedRootGroup`), so `intents/` is a drop-in; the watch
  target lists its sources explicitly (`project.pbxproj:683-729`) and therefore
  will not compile them.
- ⚠️ Do **not** use `requestAccess()` as the intent's status gate
  (`EventKitReminderDestination.swift:16-18`) — it can prompt, and mid-intent
  prompting is the failure mode the task calls out.

## Design Decisions

1. **Intents live in the app target** (`CheckStitch/Intents/`), targeting
   `CheckStitchTests` via `@testable import CheckStitch`. They need
   `ChecklistStore` and `ChecklistReminders` (both app-target) and must not drag
   AppIntents into `CheckStitchCore`, which also builds for watchOS.
2. **Partial creation becomes a first-class outcome**: add
   `case partiallyCreated(created: Int, total: Int, reason: String)` to
   `ReminderRunOutcome` with its own `errorMessage`. `ChecklistReminders`
   counts successes (it already does, `:35`) and, when the `catch` fires with
   `created > 0` and `total = checklist.items.filter { !$0.isBlank }.count`,
   returns it instead of `.failed`. `ContentView`'s switch gains the case (same
   alert, richer text) so the UI is unambiguous too.
3. **Explicit permission pre-check on the seam**: add
   `func accessStatus() -> ReminderAccessStatus` (`.fullAccess` / `.notDetermined`
   / `.denied`) to `ReminderDestinationTargeting`, implemented with
   `EKEventStore.authorizationStatus(for: .reminder)`. The intent checks it
   before any create; `.notDetermined` and `.denied`/`.restricted` get distinct
   messages ("Open CheckStitch and allow Reminders access, then ask again.").
   The in-app path keeps calling `requestAccess()` unchanged.
4. **"List My Checklists" speaks, it does not launch**: an `AppIntent returning
   some ProvidesDialog` over `store.checklists`, with a distinct empty-state
   line. No `openAppWhenRun`, no deep links — the app has no external-input
   surface and this ticket will not introduce one.
5. **Run Checklist is background too** (`openAppWhenRun` stays `false`):
   hands-free is the point; the store is read from `UserDefaults`, so a cold
   process is fine.
6. **Entity identity is `Checklist.id.uuidString`**, display name the current
   `name` — rename-stable and the same key sync uses (`Checklist.swift:92,100`).
   `defaultQuery` returns all checklists in `store.checklists` display order.
7. **Fresh, read-only store per `perform()`** (`ChecklistStore(defaults:
   AppGroup.defaults)`), per the SingleThread precedent — no shared mutable
   state with a running scene, and intents never write checklists.
8. **Dialogues come from Core/app-catalog keys via `LocalizedStringResource`,
   all six languages authored in this ticket**; keys added to
   `LocalizationFixtures.requiredKeys`.
9. **A minimal `AppShortcutsProvider`** (one phrase per intent) is in scope so
   Siri discovers the intents without a user-built shortcut. If intent-metadata
   extraction misbehaves in the gate, this is the only piece we drop: both
   intents remain reachable from Shortcuts.app.
10. **Tests are added at the unit level** — new `RunChecklistIntentTests`,
    `ChecklistEntityQueryTests`, `ListChecklistsIntentTests` (Swift Testing,
    `@MainActor`, `SpyReminderDestination` + isolated defaults), plus updates to
    `ChecklistRemindersTests` for the new case and its exact `errorMessage`.

## What We're NOT Doing

- No per-run parameters (title override, list override, due-date override) —
  deferred by the ticket.
- No reminder editing, completing, or deleting; no new Reminders writes outside
  the existing create path.
- No app foregrounding, deep links, `CFBundleURLTypes`, `onOpenURL`, or
  notification handling.
- No intents on/in the watch target; no changes to watch sync.
- No changes to the legacy `ChecklistCreator`/`ReminderCreating` path (or its
  tests) — it stays as-is.
- No store-level rename/delete intents, no import/export intents.
- No changes to in-app permission prompting, Info.plist usage strings, or
  signing/entitlements.
- No App Intent donations/`RelevantIntent`/widgets/snippet views beyond the
  dialogue result.

## Open Risks

- **App Intents + app-target concurrency**: the app sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION`; `AppIntent`/`AppEntity`/`EntityQuery`
  conformances under strict concurrency may need explicit `@MainActor`/
  `Sendable` annotations. Compiler is the oracle (`make build`).
- **Framework availability**: `AppIntents`/`AppShortcutsProvider`/`ProvidesDialog`
  API shapes are unverified in this SDK (nothing in-tree uses them) —
  SingleThread is the only on-machine precedent. Compile-verify early with a
  throwaway stub before writing real bodies.
- **Metadata extraction**: intents require the AppIntents build phase to
  emit metadata (`*.actionsdata`); this must also hold for `make build-mac`
  and `make watch-build` (which builds the same app folder's watch target).
  A metadata failure in the gate is the trigger for decision 9's fallback.
- **`.notDetermined` UX**: a first-ever user asking Siri gets "open the app
  first" rather than a prompt. Accepted (task mandates no mid-intent prompt),
  but worth confirming in the manual verification pass.
- **Stale KVS state**: an intent may read a pre-sync checklist (sync is
  launch/`scenePhase`-driven, `MyApp.swift:52-54,76-78`). Checklist *items* are
  local-authoritative, so the practical risk is low; not addressed here.
- **Localization effort**: ~6-10 new keys × 6 languages, with the
  non-English-differs canary; short phrases reduce translation risk but the
  gate fails loudly on any missing/identical value.
