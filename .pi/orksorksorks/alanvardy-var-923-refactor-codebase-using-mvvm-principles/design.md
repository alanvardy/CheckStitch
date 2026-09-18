# Design Discussion

Branch: `alanvardy-var-923-refactor-codebase-using-mvvm-principles`
Mirror: SingleThread MVVM refactor (VAR-697 / PR #100). All decisions below
were confirmed by the operator (`1A 2B 3A 4B 5A`).

## Current State

- One fat view owns most presentation **and** orchestration:
  `struct ContentView: View` (`CheckStitch/ContentView.swift:6`) mixes SwiftUI
  chrome with domain-flow logic. `@Environment store/syncService/colorScheme`
  (`:7-9`), 6 `@AppStorage` prefs (`:11-17`) and ~25 `@State` fields (`:19-46`)
  hold both view-transient UI and domain-flow state (`checklistPendingRemoval`,
  `importSession`, `conflict`, `exportDocument`, `runErrorMessage`,
  `dataActionQueue`).
- Domain calls are made inline: `createChecklist()` (`:494`),
  `createReminders(for:)` (`:500-527`), `removeChecklist(id:)` (`:528`),
  `moveChecklist(id, up:)` (`:537`). Settings staging lives in the view
  (`makeSettingsBag()` `:583`, `settingsSheetWritebacks`/`writeBack`
  `:557-591`, `SettingsDataActionQueue` `:687-703`). Import/export orchestration
  (`exportSelected()` `:613`, `importFile(at:)` `:625-…`) also lives here.
- Composition root: `@main struct MyApp: App` (`CheckStitch/MyApp.swift:10`)
  owns `store: ChecklistStore` + `syncService: ChecklistSyncService` as
  app-level `@State`, builds/starts the iOS `ChecklistSyncCoordinator`
  (`:48-65`), injects via `.environment(...)`, and flushes on `scenePhase`
  change (`:38-40, :74-78`).
- `CheckStitchCore` holds the model/seam layer: `AppEnvironment.swift:5-14`,
  `Checklist`/`ChecklistItem`/`ChecklistCodec` (`Checklist.swift:8,145,367`),
  `ReminderCreating` (`ReminderCreating.swift:9-14`),
  `ReminderDestinationTargeting` (`ReminderDestinationTargeting.swift:104-111`),
  `ReminderRunOutcome` (`:58`), `ChecklistCreator` (`ChecklistCreator.swift:30-65`),
  sync types and `WatchChecklistStore` (`ChecklistSync.swift:216+`).
- The lone existing view model sits **inside Core**: `ChecklistViewModel`
  (`ChecklistViewModel.swift:8-9`, `@Observable @MainActor public final class`)
  covering name/items/creation/spinner only (`:17-50`). The run path has no VM.
- The mirror keeps all `*ViewModel`s in the app/watch targets and never in Core
  (`SingleThread/SingleThreadApp.swift:55`, `ContentViewModel.swift:15`,
  `WatchReminderViewModel.swift:17`), with thin views delegating every mutation.
- The watch leans entirely on Core: `WatchChecklistListView.swift:15-17`,
  `WatchChecklistDetailView.swift:54-57` call `WatchChecklistStore` directly; no
  watch VMs exist, unlike `SingleThreadWatch`.
- Test targets: `CheckStitchTests` (48 files, one suite each; Swift Testing
  majority + XCTest minority; `@testable import` of app and/or Core) and the
  single XCTest `CheckStitchUITests` smoke. Fakes live in
  `CheckStitchTests/TestFixtures.swift`. Gate is `bash scripts/test.sh`.

## Desired End State

A consistent MVVM split mirroring SingleThread: **views render and delegate;
view models own presentation + domain orchestration; Core stays model/seam.**

1. New view models live in the **app target** (`CheckStitch/`) and watch target
   (`CheckStitchWatch/`), never in `CheckStitchCore`.
2. `ContentView` becomes presentation-only: it reads VM state and calls VM
   handlers; `@AppStorage` remains only for pure display prefs (`appearanceMode`,
   `textSize`), matching mirror precedent.
3. Decomposed VMs: a root list VM plus focused children for settings,
   import/export and background/appearance; creation and run are separate VMs.
4. The watch gets a thin `WatchChecklistViewModel` wrapping `WatchChecklistStore`.
5. Suites gain per-VM test files constructed directly with fakes, as the mirror
   does (`ContentViewModelTests`, `SettingsViewModelTests`, etc.).

**Correct when:** `bash scripts/test.sh` prints `gate: ok`; `ContentView.swift`
holds no `store.*` mutation calls, no `ChecklistReminders.create`, no
`ChecklistImportSession`/`ChecklistExportDocument` construction and no settings
staging; every moved behaviour has a suite that exercises it directly; and no
`*ViewModel` sits under `CheckStitchCore/Sources/`.

## Patterns to Follow

- **VM shape (mirror):** `@MainActor @Observable final class`, constructed from
  Core services, injected into views (`SingleThread/ContentViewModel.swift:15`,
  `WatchReminderViewModel.swift:17`).
- **Composition root (mirror):** root VM built at app scope and handed down
  (`SingleThreadApp.swift:55`, `AppViewModel.makeContentViewModel` :147). CheckStitch's
  equivalent is `MyApp.swift:20-23`.
- **Thin views:** mutations forwarded via VM handlers, never store calls in the
  body (`SingleThread/ContentView.swift:232/279/293/296/325` delegation sites).
- **Core stays services-only:** the seams already exist and should be injected
  into VMs, not wrapped: `AppEnvironment.swift:5-14`,
  `ReminderCreating.swift:9-14`, `ReminderDestinationTargeting.swift:104-111`,
  `ChecklistCreator.swift:33-41`.
- **Injectable timing:** `ChecklistViewModel.init(spinnerDuration: .seconds(1))`
  (`ChecklistViewModel.swift:13-16`) — keep this injection for test speed.
- **Test conventions:** Swift Testing `struct <Thing>Tests`, behaviour-named
  functions, `@Test(arguments:)`, `@MainActor` on EventKit/VM suites; fakes in
  `TestFixtures.swift`. VM suites construct the VM directly (mirror:
  `SingleThreadTests/ContentViewModelTests.swift`).
- **Gate:** `make test-unit` (fast) before `bash scripts/test.sh`; the compiler
  is the SwiftUI oracle (`conventions.md`).

**Patterns NOT to follow:**
- `*ViewModel` inside `CheckStitchCore` — that is the exact divergence from the
  mirror (`ChecklistViewModel.swift` is the exception being corrected).
- Logic-in-view: store mutations, `Task` scheduling, panel/session orchestration
  and error mapping inside view bodies (`ContentView.swift:494-703`).
- Pushing watch view logic into Core (`WatchChecklistStore`) — presentation
  state belongs in the offered watch VM, not the shared store.

## Design Decisions

1. **VM location**: app + watch targets only — Core stays model/seam. Chosen for
   exact mirror consistency; requires relocating `ChecklistViewModel.swift` out
   of `CheckStitchCore/Sources` into `CheckStitch/`.
2. **Decomposition**: root list VM + focused child VMs (settings, import/export,
   background/appearance). Chosen over one mega-VM so each concern stays
   independently testable and the root does not become the new fat file.
3. **Create/run split**: keep a creation VM (`ChecklistCreationViewModel`,
   adapted from the existing `ChecklistViewModel`) and add a
   `ChecklistRunViewModel` owning destination selection, notes, priority and
   `ReminderRunOutcome` → message mapping (`ContentView.swift:500-527`). Keeps
   each VM aligned with its existing seam and fake.
4. **Watch VM**: add a thin `WatchChecklistViewModel` in the watch target
   wrapping `WatchChecklistStore`; `WatchChecklistListView`/`DetailView` become
   presentation-only. Task explicitly requires threading the layering through
   the watch target.
5. **Migration**: incremental, gate-green per step — settings → import/export →
   run → list mutation → background/appearance. `@AppStorage` stays in the view
   for pure display prefs; domain-flow state moves to VMs (mirror precedent
   `SingleThread ContentView.swift:70-76`).
6. **Settings ownership**: a `SettingsViewModel` owns the staged
   `SettingsBindings` bag and `SettingsDataActionQueue` (`ContentView.swift:557-703`),
   exposing bindings/writeback as VM API; the existing types remain the
   persistence/transport detail underneath.
7. **Behaviour preservation**: this is a pure refactor — no user-visible
   behaviour, copy, accessibility identifiers or `UserDefaults` keys change.
   The UI smoke's accessibility ids (`createChecklistButton`, `settingsButton`,
   `emptyStateCreateButton`, `createRemindersButton`) must keep resolving.

## What We're NOT Doing

- No change to the `Checklist`/`ChecklistItem`/`ChecklistCodec` models or sync
  wire format.
- No change to EventKit seam protocols, `ChecklistCreator`, or
  `ReminderRunOutcome` semantics.
- No new DeFi/feature work: no reminders editing, completion, or deletion.
- No migration of every pref into observable state holders — display prefs stay
  `@AppStorage` in the view (mirror-faithful).
- No `swift test` / separate SPM test target; suites stay app-hosted
  `@testable` imports.
- No watch feature work beyond the VM wrapping; EventKit stays phone-side.
- No child tickets — all work lands on this branch / main ticket VAR-923.
- No project.pbxproj surgery beyond what file additions under the synchronized
  group require (new files in `CheckStitch/`, `CheckStitchWatch/`,
  `CheckStitchTests/` need none).

## Open Risks

- **Relocating `ChecklistViewModel` out of Core** breaks `@testable import
  CheckStitchCore` references in `ChecklistViewModelTests`; the suite must switch
  to `@testable import CheckStitch` and keep compiling under the macOS host leg.
- **`@Observable` + `@MainActor` under the app target's
  `SWIFT_DEFAULT_ACTOR_ISOLATION`** may differ from Core's compiled isolation;
  watch for actor-isolation diagnostics on moved types.
- **Import/export security-scoped resource handling** (`startAccessingSecurityScopedResource`,
  `ContentView.swift:625`) is easy to regress when moved; needs a focused test.
- **Settings writeback ordering** (sheet dismissal vs action-queue `perform()`,
  `:594-611`) is timing-sensitive; moving it into a VM must preserve the
  dismiss-then-present sequence.
- **Watch VM bootstrapping** — the watch app has no coordinator; the VM must own
  `store.start()`/`requestRefresh()` (`WatchChecklistListView.swift:27-30`)
  without introducing lifecycle races.
- **Scope size**: 5 modules and `ContentView`'s ~757 lines; the incremental
  order must be adhered to or the gate will stay red for long stretches.