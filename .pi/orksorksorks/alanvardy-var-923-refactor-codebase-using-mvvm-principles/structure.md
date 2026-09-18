# Structure Outline

## Approach

Pure, behaviour-preserving MVVM extraction: thin `ContentView`/watch views
delegate every mutation to `@MainActor @Observable final class` view models that
live in the app/watch targets (never `CheckStitchCore`), built once at the app
composition root and injected; Core keeps only models/seams; a direct VM suite
ships with each slice. Each slice is one concern leaving the view **end to end**
(view state → VM handler → Core seam → UI effect), gate-green, with no
user-visible change.

## Design correction (resolved: Option A)

`ChecklistViewModel` (`CheckStitchCore/.../ChecklistViewModel.swift`) is
**orphaned**: the only references are its own test (`ChecklistViewModelTests`)
and the type definition — no view or app code uses it. It also does the
*reminder-run* flow (`ChecklistCreator.create(from: items)`), not checklist
creation; the real "create checklist" is `store.create().id` (`ContentView.swift:494`).
Design decision 3 ("adapt it into `ChecklistCreationViewModel`") rests on a wrong
assumption. **Decision: delete the orphan and its test in Phase 1 (it is dead
code), and rebuild its spinner/outcome behaviour directly in the new
`ChecklistRunViewModel` in Phase 3** — no behaviour is lost because nothing calls
it, and the boundary rule lands in the first slice. No `ChecklistCreationViewModel`
is created.

## Phase 1: Walking skeleton — the VM pattern + create-checklist path

The root list view model exists in the app target, is built in `MyApp`, and the
"+" button creates a checklist end to end through it (`vm.createChecklist()` →
`store.create()` → navigation). The orphaned Core `ChecklistViewModel` and its
suite are deleted, so no `*ViewModel` lives in Core from this slice on. Green
unit tests prove the create path and the boundary rule.

**Files**: `CheckStitch/ChecklistListViewModel.swift` (new),
`CheckStitch/ContentView.swift`, `CheckStitch/MyApp.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistViewModel.swift` (deleted),
`CheckStitchTests/ChecklistViewModelTests.swift` (deleted),
`CheckStitchTests/ChecklistListViewModelTests.swift` (new).

**Key changes**:
- `@MainActor @Observable final class ChecklistListViewModel { init(store: ChecklistStore); var checklists: [Checklist] { store.checklists }; func createChecklist() -> UUID }`
- `MyApp.init()` builds it; `ContentView` reads it via `.environment(ChecklistListViewModel.self)` (keeps `ContentView()` constructible for the existing `SettingsBindingsTests` preview)

**Contract**: VMs are app-target, `@MainActor @Observable final class`es built at
the composition root, injected via `.environment`; VMs return values and the view
owns navigation/animation. Slice 2+ consume only this construction pattern.

**Tests**: `ChecklistListViewModelTests` — create returns the new id / duplicate
names disambiguate. The deleted `ChecklistViewModelTests` behaviour is not lost:
`ChecklistCreatorTests`/`ChecklistRemindersTests` cover the underlying seams,
and Phase 3 recovers its spinner/outcome assertions in `ChecklistRunViewModelTests`.
**Verify**: `make test-unit`; `make build`; `ls CheckStitchCore/Sources/CheckStitchCore/*ViewModel*` finds none.

---

## Phase 2: Edit-mode list mutations (remove + move) via the root VM

Tapping remove/move in edit mode mutates the store through
`ChecklistListViewModel`; the pending-removal id is VM state. The view keeps
`withAnimation`/dialogs.

**Files**: `CheckStitch/ChecklistListViewModel.swift`,
`CheckStitch/ContentView.swift`, `CheckStitchTests/ChecklistListViewModelTests.swift`.

**Key changes**:
- `func removeChecklist(id: UUID)` / `func moveChecklist(id: UUID, up: Bool)` — new
- `var checklistPendingRemoval: UUID?` — moved from `ContentView` `@State`

**Contract**: `ChecklistListViewModel` owns all list mutations; the view passes
intent only.

**Tests**: remove hits `store.removeChecklists`; move up/down index arithmetic;
unknown id is a no-op (sad path).
**Verify**: `make test-unit`; `make build`.

---

## Phase 3: Run reminders via `ChecklistRunViewModel` (risk front-loaded)

The per-row run button drives an injected-seam VM: spinner held ≥
`spinnerDuration`, success check, and `ReminderRunOutcome` → `runErrorMessage`
mapping. This rebuilds the deleted orphan's spinner/outcome behaviour against
the current `ChecklistReminders` seam, now directly testable.

**Files**: `CheckStitch/ChecklistRunViewModel.swift` (new),
`CheckStitch/ContentView.swift`, `CheckStitchTests/ChecklistRunViewModelTests.swift` (new).

**Key changes**:
- `@MainActor @Observable final class ChecklistRunViewModel { init(store: ChecklistStore, targeting: ReminderDestinationTargeting = EventKitReminderDestination.shared, spinnerDuration: Duration = .seconds(1)); private(set) var creating: Set<UUID>; private(set) var created: Set<UUID>; private(set) var runErrorMessage: String?; func createReminders(for id: UUID); func clearRunError() }`
- `ChecklistView` calls `vm.createReminders(for:)`; duplicate taps guarded in the VM

**Contract**: run VM is independent of the list VM; consumes the existing
`ChecklistReminders.create(from:targeting:)` seam and `SpyReminderDestination`.

**Tests**: `.created` sets then clears `created`; each failure outcome sets
`runErrorMessage`; duplicate tap while `creating` is ignored (sad path).
**Verify**: `make test-unit`; `make build`.

---

## Phase 4: Settings staging + writeback via `SettingsViewModel`

The settings sheet's staged `SettingsBindings`, writeback, and the
dismiss-then-present `SettingsDataActionQueue` move into a VM; display
`@AppStorage` prefs stay in the view (design decisions 5/6).

**Files**: `CheckStitch/SettingsViewModel.swift` (new),
`CheckStitch/ContentView.swift`, `CheckStitch/SettingsBindings.swift`,
`CheckStitchTests/SettingsViewModelTests.swift` (new),
`CheckStitchTests/SettingsBindingsTests.swift` (retarget from `ContentView()`).

**Key changes**:
- `@MainActor @Observable final class SettingsViewModel { var bag: SettingsBindings?; func begin(from: SettingsSnapshot) -> SettingsBindings; func writeBack(_ bag: SettingsBindings) -> SettingsWriteback; func stage(_ a: SettingsDataAction); func takeStaged() -> SettingsDataAction?; var showsSettings: Bool }`
- `SettingsWriteback`/`SettingsSnapshot` — small value types carrying the five prefs the view applies to `@AppStorage`
- `SettingsDataAction`/`SettingsDataActionQueue` move out of `ContentView.swift` into `SettingsBindings.swift`

**Contract**: view owns `@AppStorage` storage; VM owns staging, writeback values
and queue ordering.

**Tests**: `begin` snapshots current prefs; `writeBack` yields staged values; a
staged action is taken exactly once (sad path: double dismissal).
**Verify**: `make test-unit`; `make build`.

---

## Phase 5: Import/export via `ChecklistImportExportViewModel`

Export selection/document and the import read + FIFO conflict flow move into a
VM, preserving the security-scoped access/stop pair and the
dismiss-then-advance ordering.

**Files**: `CheckStitch/ChecklistImportExportViewModel.swift` (new),
`CheckStitch/ContentView.swift`, `CheckStitchTests/ChecklistImportExportViewModelTests.swift` (new).

**Key changes**:
- `@MainActor @Observable final class ChecklistImportExportViewModel { init(store: ChecklistStore); var exportSelection: Set<UUID>; var exportDocument: ChecklistExportDocument?; var conflict: ChecklistImportCandidate?; private(set) var isExporting/isImporting: Bool; private(set) var importErrorMessage/exportErrorMessage: String?; func beginExport(); func exportSelected(); func importFile(at url: URL); func decide(_ d: ImportDecision); func dismissConflict() }`

**Contract**: consumes `ChecklistExportDocument`/`ChecklistImportSession`
unchanged; the view presents panels/alerts from VM state.

**Tests**: export filters by selection and builds the document; empty selection
exports nothing; import read failure → system message vs format failure → the
"not a CheckStitch export" message; conflict decisions advance FIFO (sad paths).
**Verify**: `make test-unit`; `make build`; manual `make run` export/import once.

---

## Phase 6: Background image + appearance side effects

`BackgroundImageStore` lifecycle (pin-before-refresh) and the
appearance/landscape platform side effects move behind small VMs; `@AppStorage`
still drives them from the view.

**Files**: `CheckStitch/BackgroundViewModel.swift`, `CheckStitch/AppearanceViewModel.swift` (new),
`CheckStitch/ContentView.swift`, `CheckStitchTests/BackgroundViewModelTests.swift` (new).

**Key changes**:
- `@MainActor @Observable final class BackgroundViewModel { var image: BackgroundImageStore; func task(pinned: Bool) async; func setPinned(_ p: Bool) }`
- `@MainActor @Observable final class AppearanceViewModel { func appearanceModeChanged(_ m: AppearanceMode); func allowsLandscapeChanged(_ b: Bool) }`

**Contract**: `BackgroundPhotoLayer` keeps taking `imageData`/`isEnabled`/`opacity`
from the VM; platform delegates stay app-target.

**Tests**: pin is applied before the first refresh; `setPinned` forwards (sad
path: second call no-ops/refreshes per store semantics).
**Verify**: `make test-unit`; `make build`; `make build-mac`.

---

## Phase 7: Watch `WatchChecklistViewModel`

The watch list/detail views become presentation-only, delegating to a VM that
wraps `WatchChecklistStore` (start/refresh, run, `visibleItems`); EventKit stays
phone-side.

**Files**: `CheckStitchWatch/WatchChecklistViewModel.swift` (new),
`CheckStitchWatch/CheckStitchWatchApp.swift`,
`CheckStitchWatch/WatchChecklistListView.swift`,
`CheckStitchWatch/WatchChecklistDetailView.swift`.

**Key changes**:
- `@MainActor @Observable final class WatchChecklistViewModel { init(store: WatchChecklistStore); var checklists: [Checklist]; func onAppear(); func run(_ c: Checklist); func visibleItems(of c: Checklist) -> [ChecklistItem] }`
- `CheckStitchWatchApp` builds it as the watch composition root

**Contract**: only wraps `WatchChecklistStore`'s public API (`start`,
`requestRefresh`, `run`, `checklists`); no Core changes.

**Tests**: **none possible phone-side** — the watch sources are not in the
`CheckStitchTests` host target; existing `WatchChecklistStoreTests` continue to
cover the store underneath. Watch verification is compile + device.
**Verify**: `make watch-build`; manual `bash scripts/run-watch.sh` (list renders,
run button round-trips) — a sync/render ticket, not closeable on static evidence.

---

## Phase 8: Hardening and boundary lock-in

Remove any dead code left by the migration (orphan VM/test if not already
deleted), relocate remaining view-file locals (`ChecklistWidth`) if still
stranded, confirm no `*ViewModel` under Core, and prove the "correct when"
criteria.

**Files**: `CheckStitch/ContentView.swift`, `CheckStitchCore/Sources/CheckStitchCore/` (removals),
`CheckStitchTests/*` (retargets/removals).

**Key changes**: none functional — deletions and file moves only.

**Contract**: final-state invariants: no `store.*` mutation in `ContentView`, no
`ChecklistReminders.create` / `ChecklistImportSession` / `ChecklistExportDocument`
construction in `ContentView`, no settings staging in `ContentView`, no
`*ViewModel` under `CheckStitchCore/Sources/`.

**Tests**: full gate; UI smoke's accessibility ids (`createChecklistButton`,
`settingsButton`, `emptyStateCreateButton`, `createRemindersButton`) still resolve.
**Verify**: `bash scripts/test.sh` prints `gate: ok`.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` + `make build`; orphan VM/test deleted; no `*ViewModel` in Core.
- After Phase 2: list VM suite green (create/remove/move).
- After Phase 3: run VM suite green (all four failure outcomes).
- After Phase 4: settings VM suite green; `SettingsBindingsTests` retargeted.
- After Phase 5: import/export VM suite green (both import failure kinds + FIFO).
- After Phase 6: background/appearance suites green; `make build-mac` green.
- After Phase 7: `make watch-build` green + manual watch device check.
- After Phase 8: `bash scripts/test.sh` → `gate: ok`.

## Ordering note

Design decision 5 ordered settings → import/export → run → list mutation. This
outline front-loads the riskier run path (Phase 3) right after the skeleton,
per dependency → risk → value: it is the hardest async/orchestration integration
and defines the spinner/error-mapping pattern the later slices copy. If you want
design-faithful ordering, swap Phase 3 with Phases 4–5; no contract changes.