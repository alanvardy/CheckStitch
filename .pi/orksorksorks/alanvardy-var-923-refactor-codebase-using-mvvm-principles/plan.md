# Implementation Plan

## Overview

Extract CheckStitch's presentation + orchestration out of `ContentView` and the
watch views into app/watch-target `@MainActor @Observable final class` view
models, built at the composition root and injected, leaving `CheckStitchCore` as
model/seam only. Pure, behaviour-preserving refactor: no user-visible change, no
copy/accessibility-id/`UserDefaults`-key changes, gate green after every phase.

Each phase is one concern leaving the view end to end (view state → VM handler →
seam → UI effect). Phases follow `structure.md` order exactly:
1 walking skeleton + create, 2 list mutations, 3 run, 4 settings, 5
import/export, 6 background/appearance, 7 watch VM, 8 hardening.

### Construction pattern (applies to every phase)

All view models are `@MainActor @Observable final class`es in the **app target**
(`CheckStitch/`) or **watch target** (`CheckStitchWatch/`) — never
`CheckStitchCore`. The root list VM is built in `MyApp.init()`; the focused
child VMs are also built there (they need the `store`, which is not available in
a SwiftUI property initializer) and injected with `.environment(...)`.
`ContentView` reads them via `@Environment(<VM>.self)`.

> **Note on the structure's file lists:** `structure.md` names only the new VM
> file + `ContentView.swift` per phase. Because `ChecklistStore` is app-target
> and only `MyApp` can construct a store-dependent VM, every phase that
> introduces a store-dependent VM (3, 4, 5, 6) also edits `CheckStitch/MyApp.swift`.
> This is the design's "built at the composition root" contract (design decision
> 2, patterns section), not new scope. See "Deviations" at the end.

### Shared fixtures used by several phases

`CheckStitchTests/TestFixtures.swift` already provides:
`makeIsolatedDefaults()`, `makeItem(_:)`, `SpyReminderDestination`
(`ReminderDestinationTargeting` spy), `TestError`, `SpyChecklistRunner`.
`CheckStitchTests/BackgroundTestFixtures.swift` provides `FakeBackgroundFetcher`,
`GatedBackgroundFetcher`, and the `actor FetchGate` rendezvous.

Two small additions to `TestFixtures.swift` are needed (Phase 3):

```swift
// On SpyReminderDestination:
/// Awaited at the start of every `requestAccess()` — lets a suite hold a run in
/// flight and observe the duplicate-tap guard.
var onRequestAccess: (() async -> Void)?

func requestAccess() async throws -> Bool {
    if let onRequestAccess { await onRequestAccess() }
    if let accessError { throw accessError }
    return accessGranted
}
```

`FetchGate` (already declared internal in `BackgroundTestFixtures.swift`) is
reused as the gate for the duplicate-tap test.

---

## Phase 1: Walking skeleton — the VM pattern + create-checklist path

**Goal**: the root list VM exists in the app target, is built in `MyApp`, and
"+" creates a checklist end to end through it; the orphaned Core
`ChecklistViewModel` and its suite are deleted, so no `*ViewModel` lives in Core
from this slice on.

### Changes

#### 1. New root list view model
**File**: `CheckStitch/ChecklistListViewModel.swift`
**Action**: create

```swift
import CheckStitchCore
import Observation

/// Root list view model: owns the checklist list surface and its mutations.
/// The view reads `checklists` and forwards intent; navigation, animation and
/// dialogs stay in the view.
@MainActor
@Observable
final class ChecklistListViewModel {
    private let store: ChecklistStore

    init(store: ChecklistStore) {
        self.store = store
    }

    var checklists: [Checklist] { store.checklists }

    /// Creates a checklist and returns the new id. `store.create()` disambiguates
    /// a duplicate name ("New checklist 2") rather than failing, so there is
    /// always a checklist to open.
    @discardableResult
    func createChecklist() -> UUID {
        store.create().id
    }
}
```

#### 2. Delete the orphaned Core view model and its suite
**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistViewModel.swift`,
`CheckStitchTests/ChecklistViewModelTests.swift`
**Action**: delete

The only references are the type definition and its own suite (confirmed by
`rg`); no view or app code uses it. `ChecklistCreatorTests` / `ChecklistRemindersTests`
already cover the underlying seams, and Phase 3 rebuilds the spinner/outcome
behaviour in `ChecklistRunViewModel`. `AppEnvironment` (Core) and
`SpyReminderCreator` (fixtures) are **kept**: `AppEnvironment` is public Core
seam API and `SpyReminderCreator` is still used by `ChecklistCreatorTests` and
`EventKitReminderCreatorTests`.

#### 3. Composition root
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Add the VM state and build/inject it:

```swift
@State private var listViewModel: ChecklistListViewModel

init() {
    let store = ChecklistStore()
    let syncService = ChecklistSyncService(sync: UbiquitousChecklistSync(), store: store)
    syncService.start()
    _store = State(initialValue: store)
    _syncService = State(initialValue: syncService)
    _listViewModel = State(initialValue: ChecklistListViewModel(store: store))
}
```

In **both** `WindowGroup` branches (macOS and iOS), add
`.environment(listViewModel)` alongside the existing `.environment(store)`.

#### 4. View delegates the list surface + create
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- Add `@Environment(ChecklistListViewModel.self) private var listVM` next to the
  existing `store`/`syncService` environments (keep `store` — later phases still
  read it).
- Replace the list read surface with the VM:
  - `if store.checklists.isEmpty {` → `if listVM.checklists.isEmpty {`
  - `ForEach(store.checklists)` → `ForEach(listVM.checklists)`
  - `store.checklists.last?.id` → `listVM.checklists.last?.id`
  - `store.checklists.first?.id` → `listVM.checklists.first?.id`
  - `.onChange(of: store.checklists.isEmpty)` → `.onChange(of: listVM.checklists.isEmpty)`
- `createChecklist()`:

```swift
private func createChecklist() {
    path.append(listVM.createChecklist())
}
```

- `#Preview`: add `.environment(ChecklistListViewModel(store: store))`.

#### 5. New suite
**File**: `CheckStitchTests/ChecklistListViewModelTests.swift`
**Action**: create

```swift
import CheckStitchCore
@testable import CheckStitch
import Testing

@MainActor
struct ChecklistListViewModelTests {
    private func makeViewModel() -> ChecklistListViewModel {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        return ChecklistListViewModel(store: store)
    }

    @Test
    func createChecklistReturnsTheNewID() {
        let viewModel = makeViewModel()
        let id = viewModel.createChecklist()
        #expect(viewModel.checklists.count == 1)
        #expect(viewModel.checklists.first?.id == id)
    }

    @Test
    func createChecklistDisambiguatesDuplicateNames() {
        let viewModel = makeViewModel()
        _ = viewModel.createChecklist()
        _ = viewModel.createChecklist()
        #expect(viewModel.checklists.map(\.name) == ["New checklist", "New checklist 2"])
    }
}
```

### Verification

#### Automated
- [x] `make test-unit` passes (including the new `ChecklistListViewModelTests`)
- [x] `make build` passes (iOS simulator leg)
- [x] `ls CheckStitchCore/Sources/CheckStitchCore/*ViewModel*` finds no file
- [x] `rg -n "ChecklistViewModel" CheckStitchCore CheckStitch CheckStitchTests` returns only unrelated comment text in `ChecklistCreator.swift`/`ReminderCreating.swift` (no type/suite)

#### Manual
- [ ] `make run`: tapping **+** (and the empty-state "Create checklist") opens a
      new detail screen named "New checklist"; tapping it again on a fresh state
      opens "New checklist 2"

---

## Phase 2: Edit-mode list mutations (remove + move) via the root VM

**Goal**: tapping remove/move in edit mode mutates the store through
`ChecklistListViewModel`; the pending-removal id is VM state. The view keeps
`withAnimation` and the dialogs.

### Changes

#### 1. Extend the list VM
**File**: `CheckStitch/ChecklistListViewModel.swift`
**Action**: modify

```swift
/// The checklist waiting for its confirm/cancel in the remove dialog; `nil`
/// hides it.
var checklistPendingRemoval: UUID?

/// Performs the destructive half of the removal gate: a single-row batch into
/// the store's `removeChecklists` (one tombstone, one save).
func removeChecklist(id: UUID) {
    guard let index = store.checklists.firstIndex(where: { $0.id == id }) else { return }
    store.removeChecklists(at: IndexSet(integer: index))
}

/// Converts a one-row nudge into the `moved` index arithmetic: one row up is
/// `destination == index - 1`, one row down is `index + 2` (adjusted for the
/// removed element).
func moveChecklist(id: UUID, up: Bool) {
    guard let index = store.checklists.firstIndex(where: { $0.id == id }) else { return }
    store.moveChecklists(from: IndexSet(integer: index), to: up ? index - 1 : index + 2)
}
```

(`Foundation` for `IndexSet`/`UUID` is imported transitively via `CheckStitchCore`;
add `import Foundation` if the compiler asks.)

#### 2. View forwards intent; animation stays in the view
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- Delete `@State private var checklistPendingRemoval: UUID?`.
- Remove the view's `removeChecklist(id:)` and `moveChecklist(_:up:)` helpers.
- In `checklistRow` (edit branch): `checklistPendingRemoval = checklist.id` →
  `listVM.checklistPendingRemoval = checklist.id`.
- In `checklistMoveControls`: `Button { moveChecklist(checklist.id, up: true) }` →
  `Button { withAnimation { listVM.moveChecklist(id: checklist.id, up: true) } }`
  and the same for `up: false`.
- The remove `confirmationDialog` reads/writes the VM property:

```swift
.confirmationDialog(
    "Remove Checklist",
    isPresented: Binding(get: { listVM.checklistPendingRemoval != nil },
                         set: { if !$0 { listVM.checklistPendingRemoval = nil } }),
    presenting: listVM.checklistPendingRemoval
) { id in
    Button("Remove", role: .destructive) {
        listVM.checklistPendingRemoval = nil
        withAnimation { listVM.removeChecklist(id: id) }
    }
    .accessibilityIdentifier("confirmRemoveChecklistButton")
    Button("Cancel", role: .cancel) { listVM.checklistPendingRemoval = nil }
        .accessibilityIdentifier("cancelRemoveChecklistButton")
} message: { _ in
    Text("This removes the checklist and all its items.")
}
```

#### 3. Extend the suite
**File**: `CheckStitchTests/ChecklistListViewModelTests.swift`
**Action**: modify

```swift
@Test
func removeChecklistRemovesIt() {
    let viewModel = makeViewModel()
    let first = viewModel.createChecklist()
    let second = viewModel.createChecklist()
    viewModel.removeChecklist(id: first)
    #expect(viewModel.checklists.map(\.id) == [second])
}

@Test
func moveChecklistUpReorders() {
    let viewModel = makeViewModel()
    let first = viewModel.createChecklist()
    let second = viewModel.createChecklist()
    viewModel.moveChecklist(id: second, up: true)
    #expect(viewModel.checklists.map(\.id) == [second, first])
}

@Test
func moveChecklistDownReorders() {
    let viewModel = makeViewModel()
    let first = viewModel.createChecklist()
    let second = viewModel.createChecklist()
    viewModel.moveChecklist(id: first, up: false)
    #expect(viewModel.checklists.map(\.id) == [second, first])
}

@Test
func unknownIDIsANoOp() {
    let viewModel = makeViewModel()
    let only = viewModel.createChecklist()
    viewModel.removeChecklist(id: UUID())
    viewModel.moveChecklist(id: UUID(), up: true)
    #expect(viewModel.checklists.map(\.id) == [only])
}
```

### Verification

#### Automated
- [ ] `make test-unit` passes (create/remove/move + sad path)
- [ ] `make build` passes

#### Manual
- [ ] `make run`: Edit → tap minus on a row shows the confirm dialog; Remove
      removes the row with animation; up/down chevrons reorder and are disabled
      on the first/last rows

---

## Phase 3: Run reminders via `ChecklistRunViewModel` (risk front-loaded)

**Goal**: the per-row play button drives an injected-seam VM that owns spinner,
success check, and `ReminderRunOutcome` → `runErrorMessage` mapping.

### Changes

#### 1. New run view model
**File**: `CheckStitch/ChecklistRunViewModel.swift`
**Action**: create

```swift
import CheckStitchCore
import Foundation
import Observation

/// Drives one checklist's "create reminders" run. Independent of the list VM;
/// consumes the existing `ChecklistReminders` seam so tests inject
/// `SpyReminderDestination` and never touch EventKit.
@MainActor
@Observable
final class ChecklistRunViewModel {
    /// `spinnerDuration` is the minimum time the spinner stays visible once the
    /// run finishes; suites inject `.zero` to keep tests instant.
    init(
        store: ChecklistStore,
        targeting: ReminderDestinationTargeting = EventKitReminderDestination.shared,
        spinnerDuration: Duration = .seconds(1)
    ) {
        self.store = store
        self.targeting = targeting
        self.spinnerDuration = spinnerDuration
    }

    /// Checklists with a run in flight. Never persisted.
    private(set) var creating: Set<UUID> = []
    /// Checklists showing the transient success check. Never persisted.
    private(set) var created: Set<UUID> = []
    /// Message for the run-failure alert; `nil` hides it.
    private(set) var runErrorMessage: String?

    /// Guards against duplicate taps synchronously (before the first `await`),
    /// then runs one checklist.
    func createReminders(for id: UUID) async {
        guard !creating.contains(id), let checklist = store.checklist(id: id) else { return }
        creating.insert(id)
        // Hold the spinner for at least `spinnerDuration` so saving quickly
        // doesn't flash the progress feedback past the user.
        async let minimumSpinner: Void = Task.sleep(for: spinnerDuration)
        let outcome = await ChecklistReminders.create(from: checklist, targeting: targeting)
        try? await minimumSpinner
        creating.remove(id)
        switch outcome {
        case .created:
            created.insert(id)
            try? await Task.sleep(for: .seconds(1))
            created.remove(id)
        case .destinationMissing, .permissionDenied, .partiallyCreated, .failed:
            // Never flash success: nothing (or only part) was created.
            runErrorMessage = outcome.errorMessage
        }
    }

    /// Clears the failure alert.
    func clearRunError() {
        runErrorMessage = nil
    }

    private let store: ChecklistStore
    private let targeting: ReminderDestinationTargeting
    private let spinnerDuration: Duration
}
```

> `createReminders` is `async` (the structure wrote it without `async`). The
> view wraps it in `Task { await ... }`; the guard + `creating.insert` run before
> the first `await`, and MainActor task FIFO ordering makes this equivalent to
> the old synchronous mark-then-spawn. Async makes the duplicate-tap sad path
> directly testable. See "Deviations".

#### 2. Composition root
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Add `@State private var runViewModel: ChecklistRunViewModel`, build it in
`init()` with `_runViewModel = State(initialValue: ChecklistRunViewModel(store: store))`,
and inject `.environment(runViewModel)` in both `WindowGroup` branches.

#### 3. View delegates the run button
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- Add `@Environment(ChecklistRunViewModel.self) private var runVM`.
- Delete the `@State private var creating`, `created`, `runErrorMessage` fields.
- `createRemindersButton(for:)` reads VM state:

```swift
@ViewBuilder
private func createRemindersButton(for id: UUID) -> some View {
    Button {
        Task { await runVM.createReminders(for: id) }
    } label: {
        if runVM.creating.contains(id) {
            ProgressView()
                .controlSize(.small)
        } else if runVM.created.contains(id) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "play.circle.fill")
        }
    }
    .buttonStyle(.borderless)
    .disabled(runVM.creating.contains(id))
    .accessibilityLabel("Create reminders from checklist")
    .accessibilityIdentifier("createRemindersButton")
}
```

- Delete the view's `createReminders(for:)` helper.
- The failure alert binds to the VM:

```swift
.alert("Couldn't create reminders", isPresented: Binding(
    get: { runVM.runErrorMessage != nil },
    set: { if !$0 { runVM.clearRunError() } })
) {
    Button("OK", role: .cancel) {}
        .accessibilityIdentifier("runErrorMessageButton")
} message: {
    Text(runVM.runErrorMessage ?? "")
}
```

- `#Preview`: add `.environment(ChecklistRunViewModel(store: store))`.

#### 4. Fixture gate
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

Add `var onRequestAccess: (() async -> Void)?` to `SpyReminderDestination` and
await it at the top of `requestAccess()` (snippet in Overview).

#### 5. New suite
**File**: `CheckStitchTests/ChecklistRunViewModelTests.swift`
**Action**: create

```swift
import CheckStitchCore
@testable import CheckStitch
import Testing

@MainActor
struct ChecklistRunViewModelTests {
    private func makeStore(items: [String]) -> (ChecklistStore, UUID) {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let id = store.create(name: "Groceries").id
        for title in items {
            store.addItem(to: id)
            let itemID = store.checklist(id: id)?.items.last?.id ?? UUID()
            store.updateItem(checklistID: id, itemID: itemID, title: title)
        }
        return (store, id)
    }

    /// A destination with a resolvable default list, so a run can succeed.
    private func resolvableDestination() -> SpyReminderDestination {
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list", title: "Reminders")],
            defaultIdentifier: "list")
        return spy
    }

    @Test
    func createdSetsThenClearsTheSuccessCheck() async {
        let (store, id) = makeStore(items: ["one"])
        let spy = resolvableDestination()
        let viewModel = ChecklistRunViewModel(store: store, targeting: spy, spinnerDuration: .zero)

        await viewModel.createReminders(for: id)

        #expect(spy.createdTitles == ["one"])
        #expect(viewModel.runErrorMessage == nil)
        #expect(viewModel.creating.isEmpty)
        #expect(viewModel.created.isEmpty, "the success check is cleared after its flash window")
    }

    @Test(arguments: [
        ReminderRunOutcome.destinationMissing,
        .permissionDenied,
        .partiallyCreated(created: 1, total: 2, reason: "boom"),
        .failed("boom"),
    ])
    func eachFailureOutcomeSetsTheErrorMessage(_ outcome: ReminderRunOutcome) async {
        let (store, id) = makeStore(items: ["one", "two"])
        let spy = SpyReminderDestination()
        switch outcome {
        case .permissionDenied: spy.accessGranted = false
        case .destinationMissing: spy.lists = ReminderListsSnapshot(options: [], defaultIdentifier: nil)
        case .partiallyCreated: spy.createFailureCount = 1
        case .failed: spy.createError = TestError.boom
        case .created: break
        }
        let viewModel = ChecklistRunViewModel(store: store, targeting: spy, spinnerDuration: .zero)

        await viewModel.createReminders(for: id)

        #expect(viewModel.runErrorMessage == outcome.errorMessage)
        #expect(viewModel.created.isEmpty)
    }

    @Test
    func duplicateTapWhileCreatingIsIgnored() async {
        let (store, id) = makeStore(items: ["one"])
        let spy = resolvableDestination()
        let gate = FetchGate()
        spy.onRequestAccess = { await gate.wait() }
        let viewModel = ChecklistRunViewModel(store: store, targeting: spy, spinnerDuration: .zero)

        let first = Task { await viewModel.createReminders(for: id) }
        await gate.waitUntilHit()
        #expect(viewModel.creating.contains(id))

        await viewModel.createReminders(for: id)   // guard hits, returns immediately
        gate.open()
        await first.value

        #expect(spy.createdTitles.count == 1, "a second tap must not enqueue a second run")
    }

    @Test
    func unknownChecklistIDIsANoOp() async {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let spy = resolvableDestination()
        let viewModel = ChecklistRunViewModel(store: store, targeting: spy, spinnerDuration: .zero)

        await viewModel.createReminders(for: UUID())

        #expect(spy.createdTitles.isEmpty)
        #expect(viewModel.creating.isEmpty)
    }
}
```

### Verification

#### Automated
- [ ] `make test-unit` passes (success + all four failure outcomes + duplicate
      tap + unknown id)
- [ ] `make build` passes

#### Manual
- [ ] `make run`: tap play on a checklist with items → spinner ≥1s → green
      check; with Reminders permission denied → "Couldn't create reminders" alert
      with the permission message

---

## Phase 4: Settings staging + writeback via `SettingsViewModel`

**Goal**: the staged `SettingsBindings`, the writeback values, and the
dismiss-then-present `SettingsDataActionQueue` move into a VM; display
`@AppStorage` prefs stay in the view (design decisions 5/6).

### Changes

#### 1. Move the action queue and add the value types
**File**: `CheckStitch/SettingsBindings.swift`
**Action**: modify

Move `SettingsDataAction` and `SettingsDataActionQueue` out of
`ContentView.swift` (byte-identical, so `SettingsDataActionQueueTests` keeps
passing) and add:

```swift
/// The five prefs the settings sheet stages, read from the view's `@AppStorage`
/// before the sheet opens.
struct SettingsSnapshot: Equatable {
    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool
    var textSize: TextSize
    var allowsLandscape: Bool
}

/// The staged prefs handed back for the view to write to `@AppStorage`.
struct SettingsWriteback: Equatable {
    var backgroundEnabled: Bool
    var backgroundFadePercent: Int
    var backgroundPinned: Bool
    var textSize: TextSize
    var allowsLandscape: Bool
}
```

#### 2. New settings view model
**File**: `CheckStitch/SettingsViewModel.swift`
**Action**: create

```swift
import Observation

/// Owns the staged settings bag and the Settings-menu action queue. The view
/// keeps the `@AppStorage` prefs and applies the VM's writeback to them.
@MainActor
@Observable
final class SettingsViewModel {
    var bag: SettingsBindings?
    var showsSettings = false
    private var dataActionQueue = SettingsDataActionQueue()

    /// Snapshots the current prefs into a fresh staging bag and presents the
    /// sheet. Returns the bag for convenience.
    @discardableResult
    func begin(from snapshot: SettingsSnapshot) -> SettingsBindings {
        let bag = SettingsBindings(
            backgroundEnabled: snapshot.backgroundEnabled,
            backgroundFadePercent: snapshot.backgroundFadePercent,
            backgroundPinned: snapshot.backgroundPinned,
            textSize: snapshot.textSize,
            allowsLandscape: snapshot.allowsLandscape)
        self.bag = bag
        showsSettings = true
        return bag
    }

    /// Projects the staged bag into the values the view persists.
    func writeBack(_ bag: SettingsBindings) -> SettingsWriteback {
        SettingsWriteback(
            backgroundEnabled: bag.backgroundEnabled,
            backgroundFadePercent: bag.backgroundFadePercent,
            backgroundPinned: bag.backgroundPinned,
            textSize: bag.textSize,
            allowsLandscape: bag.allowsLandscape)
    }

    /// Stages an import/export request and closes the sheet so the root-owned
    /// file panel presents unobstructed.
    func stage(_ action: SettingsDataAction) {
        dataActionQueue.stage(action)
        showsSettings = false
    }

    /// Hands the staged action over exactly once.
    func takeStaged() -> SettingsDataAction? {
        dataActionQueue.take()
    }

    /// Clears the staging bag once the sheet has dismissed.
    func sheetDidDismiss() {
        bag = nil
    }
}
```

#### 3. Composition root
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Add `@State private var settingsViewModel: SettingsViewModel`, build it in
`init()`, and inject `.environment(settingsViewModel)` in both branches.

#### 4. View keeps `@AppStorage`, delegates staging
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- Add `@Environment(SettingsViewModel.self) private var settingsVM`.
- Delete `@State private var isShowingSettings`, `@State private var dataActionQueue`,
  `@State private var settingsBag`.
- Both settings buttons (iOS + macOS branches) open the sheet through the VM:

```swift
Button {
    settingsVM.begin(from: SettingsSnapshot(
        backgroundEnabled: backgroundEnabled,
        backgroundFadePercent: backgroundFadePercent,
        backgroundPinned: backgroundPinned,
        textSize: textSize,
        allowsLandscape: allowsLandscape))
} label: { /* unchanged label */ }
```

- The sheet and dismissal sequence:

```swift
.sheet(isPresented: Binding(get: { settingsVM.showsSettings },
                            set: { settingsVM.showsSettings = $0 })) {
    if let bag = settingsVM.bag {
        settingsSheetWritebacks(bag)
    }
}
.onChange(of: settingsVM.showsSettings) { _, showing in
    guard !showing else { return }
    settingsVM.sheetDidDismiss()
    guard let action = settingsVM.takeStaged() else { return }
    // The file panels live on this root view: a sheet-nested `.fileExporter`
    // never presents on macOS. So the settings sheet has to finish dismissing
    // before the panel is asked for.
    Task {
        try? await Task.sleep(for: .milliseconds(400))
        perform(action)
    }
}
```

- `settingsSheetWritebacks(_:)`: replace each `writeBack(bag)` with
  `applySettings(settingsVM.writeBack(bag))`; keep the five `.onChange` lines and
  `backgroundImage: backgroundImage` (Phase 6 changes this to `backgroundVM.image`).
- Delete `makeSettingsBag()` and `writeBack(_:)`; add:

```swift
/// Applies the VM's staged writeback to the `@AppStorage`-backed properties.
func applySettings(_ writeback: SettingsWriteback) {
    backgroundEnabled = writeback.backgroundEnabled
    backgroundFadePercent = writeback.backgroundFadePercent
    backgroundPinned = writeback.backgroundPinned
    textSize = writeback.textSize
    allowsLandscape = writeback.allowsLandscape
}
```

- `requestDataAction(_:)` → `settingsVM.stage(action)` (the VM sets
  `showsSettings = false`).
- Delete the `SettingsDataAction` / `SettingsDataActionQueue` definitions at the
  bottom of `ContentView.swift` (now in `SettingsBindings.swift`).

#### 5. Retarget `SettingsBindingsTests`
**File**: `CheckStitchTests/SettingsBindingsTests.swift`
**Action**: modify

- Keep `defaultsMatchPreferenceDefaults` and `stagedMutationDoesNotTouchUserDefaults`.
- Replace `snapshotReadsCurrentUserDefaults` (which used `ContentView.makeSettingsBag()`)
  with a VM-level test in `SettingsViewModelTests` (below).
- Replace `writeBackPersistsEachKey`'s `view.writeBack(bag)` with
  `ContentView().applySettings(SettingsViewModel().writeBack(bag))` and keep the
  `UserDefaults` assertions — this still covers the `@AppStorage` bridge the view
  owns, without the deleted `writeBack`/`makeSettingsBag`.

#### 6. New suite
**File**: `CheckStitchTests/SettingsViewModelTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import Testing

@MainActor
struct SettingsViewModelTests {
    @Test
    func beginStagesTheSnapshotAndPresents() {
        let viewModel = SettingsViewModel()
        let bag = viewModel.begin(from: SettingsSnapshot(
            backgroundEnabled: false,
            backgroundFadePercent: 70,
            backgroundPinned: true,
            textSize: .extraLarge,
            allowsLandscape: false))

        #expect(viewModel.showsSettings)
        #expect(viewModel.bag === bag)
        #expect(bag.backgroundEnabled == false)
        #expect(bag.backgroundFadePercent == 70)
        #expect(bag.backgroundPinned)
        #expect(bag.textSize == .extraLarge)
        #expect(bag.allowsLandscape == false)
    }

    @Test
    func writeBackYieldsTheStagedValues() {
        let viewModel = SettingsViewModel()
        let bag = SettingsBindings(
            backgroundEnabled: false, backgroundFadePercent: 10,
            backgroundPinned: true, textSize: .large, allowsLandscape: false)

        let writeback = viewModel.writeBack(bag)

        #expect(writeback == SettingsWriteback(
            backgroundEnabled: false, backgroundFadePercent: 10,
            backgroundPinned: true, textSize: .large, allowsLandscape: false))
    }

    @Test
    func stagedActionIsTakenExactlyOnce() {
        let viewModel = SettingsViewModel()
        viewModel.begin(from: SettingsSnapshot(
            backgroundEnabled: true, backgroundFadePercent: 50,
            backgroundPinned: false, textSize: .system, allowsLandscape: true))

        viewModel.stage(.export)

        #expect(!viewModel.showsSettings)
        #expect(viewModel.takeStaged() == .export)
        #expect(viewModel.takeStaged() == nil, "a dismissal replay must not open a second panel")
    }

    @Test
    func sheetDidDismissClearsTheBag() {
        let viewModel = SettingsViewModel()
        _ = viewModel.begin(from: SettingsSnapshot(
            backgroundEnabled: true, backgroundFadePercent: 50,
            backgroundPinned: false, textSize: .system, allowsLandscape: true))

        viewModel.sheetDidDismiss()

        #expect(viewModel.bag == nil)
    }
}
```

### Verification

#### Automated
- [ ] `make test-unit` passes (`SettingsViewModelTests` + retargeted
      `SettingsBindingsTests` + unchanged `SettingsDataActionQueueTests`)
- [ ] `make build` passes

#### Manual
- [ ] `make run`: open Settings, toggle a background pref, close the sheet →
      value survives relaunch; Settings → Export/Import opens the panel only
      after the sheet has dismissed

---

## Phase 5: Import/export via `ChecklistImportExportViewModel`

**Goal**: export selection/document and the import read + FIFO conflict flow
move into a VM, preserving the security-scoped access/stop pair and the
dismiss-then-advance ordering.

### Changes

#### 1. New import/export view model
**File**: `CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: create

```swift
import CheckStitchCore
import Foundation
import Observation

/// Drives the root screen's import/export flow: the export multi-select, the
/// export document, the file read, and the FIFO conflict queue. The view owns
/// the panels/alerts and presents them from this state.
@MainActor
@Observable
final class ChecklistImportExportViewModel {
    init(store: ChecklistStore) {
        self.store = store
    }

    var exportSelection: Set<UUID> = []
    var exportDocument: ChecklistExportDocument?
    var conflict: ChecklistImportCandidate?
    var isShowingExport = false
    private(set) var isExporting = false
    private(set) var isImporting = false
    private(set) var importErrorMessage: String?
    private(set) var exportErrorMessage: String?
    private var importSession: ChecklistImportSession?

    /// Opens the export multi-select with nothing selected.
    func beginExport() {
        exportSelection = []
        isShowingExport = true
    }

    /// Opens the file importer.
    func beginImport() {
        isImporting = true
    }

    func dismissExportSelection() { isShowingExport = false }
    func dismissExport() { isExporting = false }
    func dismissImport() { isImporting = false }
    func clearImportError() { importErrorMessage = nil }
    func clearExportError() { exportErrorMessage = nil }

    /// Builds the document for the current selection and hands it to the
    /// exporter. An empty selection exports nothing.
    func exportSelected() {
        isShowingExport = false
        let selected = store.checklists.filter { exportSelection.contains($0.id) }
        guard !selected.isEmpty else { return }
        do {
            exportDocument = try ChecklistExportDocument(checklists: selected)
            isExporting = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    func exportFailed(_ error: Error) {
        exportErrorMessage = error.localizedDescription
    }

    func importFailed(_ error: Error) {
        importErrorMessage = error.localizedDescription
    }

    /// Reads the picked file under a security-scoped access/stop pair, then
    /// prepares an import session. A read failure reports the system message;
    /// a format failure reports the CheckStitch-specific one.
    func importFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            importErrorMessage = error.localizedDescription
            return
        }

        let session = ChecklistImportSession(store: store)
        do {
            try session.prepare(data: data)
        } catch let error as ChecklistImportError {
            importErrorMessage = error.message
            return
        } catch {
            importErrorMessage = "This file isn't a CheckStitch export."
            return
        }
        importSession = session
        conflict = session.pending.first
    }

    /// Applies one decision to the current conflict and advances the queue.
    func decide(_ decision: ImportDecision) {
        guard let current = conflict else { return }
        conflict = nil
        importSession?.decide(decision, for: current.id)
        advanceConflict()
    }

    /// Handles SwiftUI's own dismissal of the conflict dialog (setter fires
    /// `false`): keep the existing checklist and advance, exactly once.
    func dismissConflict() {
        guard let current = conflict else { return }
        conflict = nil
        importSession?.decide(.keepExisting, for: current.id)
        advanceConflict()
    }

    /// Re-presents after the current dismissal completes, so the next conflict
    /// in the FIFO queue is shown until the queue is empty.
    private func advanceConflict() {
        Task { @MainActor in
            conflict = importSession?.pending.first
        }
    }

    private let store: ChecklistStore
}
```

#### 2. Composition root
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Add `@State private var importExportViewModel: ChecklistImportExportViewModel`,
build it in `init()` with the store, and inject `.environment(importExportViewModel)`
in both branches.

#### 3. View presents panels from VM state
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- Add `@Environment(ChecklistImportExportViewModel.self) private var importExportVM`.
- Delete the `@State` fields `isShowingExport`, `exportSelection`,
  `exportDocument`, `isExporting`, `isImporting`, `importSession`, `conflict`,
  `importErrorMessage`, `exportErrorMessage`.
- Delete the view helpers `beginExport()`, `exportSelected()`, `importFile(at:)`,
  `conflictPresented`, `choose(_:)`, `advanceConflict()`.
- Replace `perform(_:)`:

```swift
private func perform(_ action: SettingsDataAction) {
    switch action {
    case .export: importExportVM.beginExport()
    case .importChecklists: importExportVM.beginImport()
    }
}
```

- Import alert:

```swift
.alert("Couldn't import",
       isPresented: Binding(get: { importExportVM.importErrorMessage != nil },
                            set: { if !$0 { importExportVM.clearImportError() } })) {
    Button("OK", role: .cancel) {}
} message: { Text(importExportVM.importErrorMessage ?? "") }
```

- Export selection sheet + exporter:

```swift
.sheet(isPresented: Binding(get: { importExportVM.isShowingExport },
                            set: { if !$0 { importExportVM.dismissExportSelection() } })) {
    ExportChecklistsView(
        selection: Binding(get: { importExportVM.exportSelection },
                           set: { importExportVM.exportSelection = $0 })) {
        importExportVM.exportSelected()
    }
}
.fileExporter(isPresented: Binding(get: { importExportVM.isExporting },
                                   set: { if !$0 { importExportVM.dismissExport() } }),
              document: importExportVM.exportDocument,
              contentType: .json,
              defaultFilename: ChecklistExport.filename()) { result in
    if case .failure(let error) = result { importExportVM.exportFailed(error) }
}
```

- Importer:

```swift
.fileImporter(isPresented: Binding(get: { importExportVM.isImporting },
                                   set: { if !$0 { importExportVM.dismissImport() } }),
              allowedContentTypes: [.json]) { result in
    switch result {
    case .success(let url): importExportVM.importFile(at: url)
    case .failure(let error): importExportVM.importFailed(error)
    }
}
```

- Conflict dialog:

```swift
.confirmationDialog("Name conflict",
                    isPresented: Binding(get: { importExportVM.conflict != nil },
                                         set: { if !$0 { importExportVM.dismissConflict() } }),
                    presenting: importExportVM.conflict) { candidate in
    Button("Replace") { importExportVM.decide(.replace) }
    Button("Keep Both") { importExportVM.decide(.keepBoth) }
    Button("Keep Existing", role: .cancel) { importExportVM.decide(.keepExisting) }
} message: { candidate in
    Text("“\(candidate.checklist.name)” already exists.")
}
```

- Export error alert:

```swift
.alert("Couldn't export",
       isPresented: Binding(get: { importExportVM.exportErrorMessage != nil },
                            set: { if !$0 { importExportVM.clearExportError() } })) {
    Button("OK", role: .cancel) {}
} message: { Text(importExportVM.exportErrorMessage ?? "") }
```

- `#Preview`: add `.environment(ChecklistImportExportViewModel(store: store))`.

#### 4. New suite
**File**: `CheckStitchTests/ChecklistImportExportViewModelTests.swift`
**Action**: create

```swift
import CheckStitchCore
@testable import CheckStitch
import Testing

@MainActor
struct ChecklistImportExportViewModelTests {
    private func makeStore(names: [String]) -> ChecklistStore {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        for name in names { _ = store.create(name: name) }
        return store
    }

    /// Writes `data` to a unique temp file and returns its URL.
    private func writeTempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    @Test
    func exportFiltersBySelectionAndBuildsTheDocument() throws {
        let store = makeStore(names: ["Groceries", "Packing"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = [store.checklists[0].id]

        viewModel.exportSelected()

        #expect(viewModel.isExporting)
        #expect(viewModel.exportDocument != nil)
        #expect(!viewModel.isShowingExport)
    }

    @Test
    func emptySelectionExportsNothing() {
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = []

        viewModel.exportSelected()

        #expect(viewModel.exportDocument == nil)
        #expect(!viewModel.isExporting)
    }

    @Test
    func readFailureReportsTheSystemMessage() {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")

        viewModel.importFile(at: missing)

        #expect(viewModel.importErrorMessage != nil)
        #expect(viewModel.importErrorMessage != "This file isn't a CheckStitch export.")
    }

    @Test
    func formatFailureReportsTheNotAnExportMessage() throws {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let url = try writeTempFile(Data("not json".utf8))

        viewModel.importFile(at: url)

        #expect(viewModel.importErrorMessage == "This file isn't a CheckStitch export.")
    }

    @Test
    func conflictDecisionsAdvanceTheFIFOQueue() async throws {
        // Export two same-named checklists, import into a store that already has
        // that name → two conflicts, presented in file order.
        let exported = try ChecklistExport.data(checklists: [
            Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")]),
            Checklist(name: "Groceries", items: [ChecklistItem(title: "Eggs")]),
        ])
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)

        viewModel.importFile(at: try writeTempFile(exported))

        let first = viewModel.conflict
        #expect(first != nil)
        viewModel.decide(.keepExisting)
        // `advanceConflict` defers to the next main-actor turn.
        await Task.yield()
        #expect(viewModel.conflict != nil)
        #expect(viewModel.conflict?.id != first?.id)
        viewModel.decide(.keepBoth)
        await Task.yield()
        #expect(viewModel.conflict == nil)
    }
}
```

> The FIFO test is `async` (above) because `advanceConflict` defers to the next
> main-actor turn. If a single `Task.yield()` proves insufficient on the macOS
> host, loop `for _ in 0..<10 where viewModel.conflict != nil { await Task.yield() }`
> — the deferral is one main-actor turn.

### Verification

#### Automated
- [ ] `make test-unit` passes (export filter/empty; read vs format failure; FIFO
      advance)
- [ ] `make build` passes
- [ ] `rg -n "ChecklistImportSession|ChecklistExportDocument|startAccessingSecurityScopedResource" CheckStitch/ContentView.swift` finds nothing

#### Manual
- [ ] `make run`: Settings → Export → select a subset → share sheet writes a JSON
      file; re-import it into the same list → one "Name conflict" dialog per
      conflicting checklist, in file order; a non-export `.json` shows "This file
      isn't a CheckStitch export."

---

## Phase 6: Background image + appearance side effects

**Goal**: `BackgroundImageStore` lifecycle (pin-before-refresh) and the
appearance/landscape platform side effects move behind small VMs; `@AppStorage`
still drives them from the view.

### Changes

#### 1. New background view model
**File**: `CheckStitch/BackgroundViewModel.swift`
**Action**: create

```swift
import Observation

/// Owns the background-image store's lifecycle so `ContentView` only renders its
/// state. The `@AppStorage("backgroundPinned")` pref still drives it.
@MainActor
@Observable
final class BackgroundViewModel {
    var image: BackgroundImageStore

    init(image: BackgroundImageStore = BackgroundImageStore()) {
        self.image = image
    }

    /// Pins BEFORE the first refresh so a pinned cold launch never refetches a
    /// stale stored image (mirrors SingleThread's ordering).
    func task(pinned: Bool) async {
        await image.setPinned(pinned)
        await image.refreshIfNeeded()
    }

    func setPinned(_ pinned: Bool) async {
        await image.setPinned(pinned)
    }
}
```

#### 2. New appearance view model
**File**: `CheckStitch/AppearanceViewModel.swift`
**Action**: create

```swift
import Observation

/// Forwards appearance/orientation preference changes to the platform
/// delegates. Stateless: the `@AppStorage` prefs remain the source of truth.
@MainActor
@Observable
final class AppearanceViewModel {
    func appearanceModeChanged(_ mode: AppearanceMode) {
        #if os(iOS)
            AppDelegate.applyAppearance(mode)
        #endif
        #if os(macOS)
            MacAppDelegate.applyAppearance(mode)
        #endif
    }

    func allowsLandscapeChanged(_ allowsLandscape: Bool) {
        #if os(iOS)
            AppDelegate.applyLock(allowsLandscape: allowsLandscape)
        #endif
    }
}
```

#### 3. Composition root
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

Add `@State private var backgroundViewModel: BackgroundViewModel` and
`@State private var appearanceViewModel: AppearanceViewModel`, build both in
`init()`, and inject `.environment(backgroundViewModel)` /
`.environment(appearanceViewModel)` in both branches.

#### 4. View renders VM state
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- Add `@Environment(BackgroundViewModel.self) private var backgroundVM` and
  `@Environment(AppearanceViewModel.self) private var appearanceVM`.
- Delete `@State private var backgroundImage = BackgroundImageStore()`.
- `BackgroundPhotoLayer(imageData: backgroundVM.image.imageData, ...)`.
- `.task { await backgroundVM.task(pinned: backgroundPinned) }`.
- `.onChange(of: backgroundPinned) { _, pin in Task { await backgroundVM.setPinned(pin) } }`.
- `.onChange(of: appearanceMode) { _, new in appearanceVM.appearanceModeChanged(new) }`
  (delete the inline `#if os` blocks).
- `.onChange(of: allowsLandscape) { _, new in appearanceVM.allowsLandscapeChanged(new) }`.
- `settingsSheetWritebacks`: `backgroundImage: backgroundVM.image`.
- `#Preview`: add `.environment(BackgroundViewModel())` and
  `.environment(AppearanceViewModel())`.

#### 5. New suite
**File**: `CheckStitchTests/BackgroundViewModelTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct BackgroundViewModelTests {
    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let imageURL = URL(string: "https://images.unsplash.com/photo-1.jpg")!

    private func makeViewModel(pinned: Bool) -> (BackgroundViewModel, URL) {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = BackgroundImageStore(client: fake, directory: directory)
        return (BackgroundViewModel(image: store), directory)
    }

    private func payloadJSON() -> Data {
        Data(("{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"NEOM\","
            + "\"photographer_url\":\"https://unsplash.com/@neom\",\"created_at\":\"2026-01-01\"}").utf8)
    }

    @Test
    func taskPinsThenRefreshes() async {
        let (viewModel, _) = makeViewModel(pinned: true)

        await viewModel.task(pinned: true)

        #expect(viewModel.image.isPinned)
        #expect(viewModel.image.imageData != nil, "a pinned blank store still fetches its first photo")
    }

    @Test
    func setPinnedForwards() async {
        let (viewModel, _) = makeViewModel(pinned: false)

        await viewModel.setPinned(true)
        #expect(viewModel.image.isPinned)

        await viewModel.setPinned(false)
        #expect(!viewModel.image.isPinned)
    }
}
```

> The precise "pin applied before the first refresh" ordering can additionally
> be pinned with `GatedBackgroundFetcher` + `FetchGate`: park the endpoint fetch,
> assert `viewModel.image.isPinned` is already `true` while parked, then
> `gate.open()`. Include this if the simple assertion above is judged too weak.

### Verification

#### Automated
- [ ] `make test-unit` passes (`BackgroundViewModelTests`)
- [ ] `make build` passes
- [ ] `make build-mac` passes (the appearance VM carries the `#if os(macOS)` leg)

#### Manual
- [ ] `make build-mac-signed` + launch: the background photo still loads; toggling
      the theme in Settings still updates the window chrome on macOS and the app
      appearance on iOS

---

## Phase 7: Watch `WatchChecklistViewModel`

**Goal**: the watch list/detail views become presentation-only, delegating to a
VM wrapping `WatchChecklistStore` (start/refresh, run, visible items). EventKit
stays phone-side.

### Changes

#### 1. New watch view model
**File**: `CheckStitchWatch/WatchChecklistViewModel.swift`
**Action**: create

```swift
import CheckStitchCore
import Observation

/// Wraps the watch's `WatchChecklistStore` so the list/detail views only render
/// and delegate. EventKit stays phone-side.
@MainActor
@Observable
final class WatchChecklistViewModel {
    private let store: WatchChecklistStore

    init(store: WatchChecklistStore) {
        self.store = store
    }

    var checklists: [Checklist] { store.checklists }

    /// Activates the transport and asks the phone for a fresh snapshot.
    func onAppear() {
        store.start()
        store.requestRefresh()
    }

    /// Sends a run request and returns its run id (the detail screen tracks it).
    @discardableResult
    func run(_ checklist: Checklist) -> UUID {
        store.run(checklist)
    }

    /// The live store copy once a refresh lands, falling back to the pushed seed.
    func current(_ checklist: Checklist) -> Checklist {
        store.checklists.first { $0.id == checklist.id } ?? checklist
    }

    /// Blank rows are never turned into reminders, so the watch hides them too.
    func visibleItems(of checklist: Checklist) -> [ChecklistItem] {
        current(checklist).items.filter { !$0.isBlank }
    }

    func phase(runID: UUID?) -> RunPhase {
        runID.map { store.runPhase(runID: $0) } ?? .idle
    }
}
```

#### 2. Watch composition root
**File**: `CheckStitchWatch/CheckStitchWatchApp.swift`
**Action**: modify

```swift
@main
struct CheckStitchWatchApp: App {
    @State private var viewModel = WatchChecklistViewModel(
        store: WatchChecklistStore(transport: WatchSyncAdapter()))

    var body: some Scene {
        WindowGroup {
            WatchChecklistListView()
                .environment(viewModel)
                .environment(\.locale, AppLocaleState.current.effectiveLocale)
        }
    }
}
```

#### 3. List view delegates
**File**: `CheckStitchWatch/WatchChecklistListView.swift`
**Action**: modify

- `@Environment(WatchChecklistStore.self) private var store` →
  `@Environment(WatchChecklistViewModel.self) private var viewModel`.
- `store.checklists` → `viewModel.checklists` (both occurrences).
- `.task { store.start(); store.requestRefresh() }` → `.task { viewModel.onAppear() }`.

#### 4. Detail view delegates
**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: modify

- `@Environment(WatchChecklistStore.self) private var store` →
  `@Environment(WatchChecklistViewModel.self) private var viewModel`; keep
  `@State private var runID: UUID?`.
- `current` → `viewModel.current(checklist)`; `visibleItems` →
  `viewModel.visibleItems(of: checklist)`; `phase` → `viewModel.phase(runID: runID)`.
- Run button: `runID = viewModel.run(checklist)`.

#### 5. Tests

**None possible phone-side** — the watch sources are not in the `CheckStitchTests`
host target. Existing `WatchChecklistStoreTests` continue to cover the store
underneath. Watch verification is compile + device.

### Verification

#### Automated
- [ ] `make watch-build` passes
- [ ] `make build` passes (the iOS app still embeds the watch target)

#### Manual (sync/render ticket — not closeable on static evidence)
- [ ] `bash scripts/run-watch.sh`: the watch list renders the phone's checklists;
      opening one shows its non-blank items; **Create reminders** shows
      "Sending…" then "Created" and the phone creates the reminders

---

## Phase 8: Hardening and boundary lock-in

**Goal**: remove anything left dead by the migration, confirm the invariants,
and prove the "correct when" criteria.

### Changes

#### 1. Remove the now-unused store environment from `ContentView`
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

After Phase 5, `ContentView` no longer references `store`. Remove
`@Environment(ChecklistStore.self) private var store` (keep `MyApp`'s
`.environment(store)` — `ChecklistDetailView`, `ExportChecklistsView` and the
sync coordinator still need it). Verify with:

```bash
rg -n "\bstore\b" CheckStitch/ContentView.swift
```

If any reference remains, keep the property and note it.

#### 2. `ChecklistWidth` stays put (no move)
**File**: `CheckStitch/ContentView.swift`
**Action**: none

The structure's Phase 8 mentions relocating `ChecklistWidth` "if still
stranded". It is **not** stranded: `ContentView` still calls
`ChecklistWidth.maxContentWidth(viewportWidth:)` in two places, and
`ChecklistWidthTests` / `CardPlateTests` reference it. Moving it would be churn
with no behaviour change. No action.

#### 3. No dead code left
**Files**: `CheckStitchCore/Sources/CheckStitchCore/`, `CheckStitchTests/`
**Action**: none expected

Phase 1 deleted the orphan `ChecklistViewModel` + suite. `AppEnvironment`
(Core) is now unreferenced internally but is public Core seam API and is
deliberately retained (out of scope per design "What We're NOT Doing").
`SpyReminderCreator` remains in use by `ChecklistCreatorTests` /
`EventKitReminderCreatorTests`.

### Verification

#### Automated
- [ ] `bash scripts/test.sh` prints `gate: ok`
- [ ] No `*ViewModel` under Core: `ls CheckStitchCore/Sources/CheckStitchCore/*ViewModel*` finds nothing
- [ ] No store mutation in `ContentView`:
      `rg -n "store\.(create|removeChecklists|moveChecklists|addItem|updateItem|removeItems|moveItems|importInsert|importReplace|rename|setDestination|setPrefixesReminderNumbers|delete|flushPendingSave)" CheckStitch/ContentView.swift` finds nothing
- [ ] No run/import/export construction in `ContentView`:
      `rg -n "ChecklistReminders\.create|ChecklistImportSession|ChecklistExportDocument" CheckStitch/ContentView.swift` finds nothing
- [ ] No settings staging in `ContentView`:
      `rg -n "SettingsBindings\(|dataActionQueue|makeSettingsBag" CheckStitch/ContentView.swift` finds nothing
- [ ] UI smoke accessibility ids still resolve: `createChecklistButton`,
      `settingsButton`, `emptyStateCreateButton`, `createRemindersButton`
      (covered by `make test-ui` inside the gate)

#### Manual
- [ ] `make run` on a simulator: create a checklist, edit items, run it, open
      Settings, export/import — no behaviour, copy or layout change vs. before
      the refactor

---

## Deviations from `structure.md`

1. **`MyApp.swift` edits in Phases 3–6.** The structure listed only the new VM
   file + `ContentView.swift`. Store-dependent child VMs cannot be built in a
   SwiftUI property initializer (no environment access), so they are built at
   the composition root as the design's construction-pattern contract requires.
2. **`ChecklistRunViewModel.createReminders(for:)` is `async`.** The structure
   wrote it sync. The view wraps it in `Task`; the duplicate-tap guard still runs
   before the first `await` on the MainActor, so behaviour is preserved, and the
   sad path becomes directly testable.
3. **`ChecklistImportExportViewModel` gains `isShowingExport`, `beginImport()`,
   `dismissExportSelection()`, `dismissExport()`, `dismissImport()`,
   `exportFailed(_:)`, `importFailed(_:)`, `clearImportError()`,
   `clearExportError()`.** The structure listed `isExporting`/`isImporting` as
   `private(set)`; SwiftUI's `fileExporter`/`fileImporter`/`sheet` bindings must
   be able to write `false`, so dismiss methods stand in for direct setters. The
   export-selection sheet's presented flag was not in the structure's API list.
4. **`WatchChecklistViewModel.run(_:)` returns `UUID`** (structure: no return)
   and gains `current(_:)` / `phase(runID:)` so the detail screen keeps its
   per-screen `runID` and can render `RunPhase` without touching the store.
5. **`SettingsBindingsTests` still constructs `ContentView()`** for the
   `@AppStorage`-bridge assertion (`applySettings`). The VM-facing assertions
   move to `SettingsViewModelTests`. The structure's "retarget from
   `ContentView()`" is honoured for the deleted `makeSettingsBag`/`writeBack`.
6. **Phase 8's `ChecklistWidth` relocation is a no-op** (still used by
   `ContentView`), as is the "orphan VM/test" deletion (done in Phase 1).
7. **`ChecklistDetailView` is out of scope** (not named in any phase); it keeps
   its direct store usage, matching the structure's explicit phase file lists.

No open questions remain.
