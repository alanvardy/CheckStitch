# Implementation Plan

## Overview

Replace the stored `Checklist.multiple: Int` with `Checklist.scaling: Scaling`
(`.fixed(Int)` / `.prompt(lastFixed: Int)`), encoded with the additive dual-key
codec (`multiple` shadow + `scalingMode`, no `currentVersion` bump). A Prompt
checklist asks for a number at run time and scales by it through the existing
per-run `multipleOverride` seam — in-app via a validated sheet, via the App
Intent through a `requestValue` seam — and never writes the number back.

Working documents: `structure.md`, `design.md`, `research.md`, `conventions.md`
in this directory. All line references below are to those artifacts or to the
cited source regions.

---

## Phase 0: `Scaling` type end to end, `.fixed` unchanged (walking skeleton)

**Goal**: identical behaviour, but the payload carries `multiple` + `scalingMode`
and the in-memory model is the enum. Genuine horizontal exception: the stored-type
swap is atomic across all consumers; it is still one green commit.

### Changes

#### 1. `Scaling` type and the `Checklist` stored-property swap

**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Insert directly above `public struct Checklist` (currently `:171`):

```swift
/// How a checklist's `((n))` markers are scaled into reminder titles and
/// descriptions. The legacy numeric view of this value is `Checklist.multiple`.
public enum Scaling: Equatable, Hashable, Sendable {
    /// Always multiply markers by this factor (clamped into `Checklist.multipleRange`).
    case fixed(Int)
    /// Ask for the factor at run time. `lastFixed` is the value restored when the
    /// user switches back to `.fixed`, and is exactly the value the legacy
    /// `multiple` key carries so an older build keeps working.
    case prompt(lastFixed: Int)

    /// The number this mode stands for — the fixed factor, or the prompt's
    /// remembered default. Always clamped through the single clamp source.
    public var number: Int {
        switch self {
        case .fixed(let value): return Checklist.clampedMultiple(value)
        case .prompt(let lastFixed): return Checklist.clampedMultiple(lastFixed)
        }
    }

    /// The multiplier a *display* surface uses when no number has been asked for:
    /// a prompt's `lastFixed` is not the multiplier for this run, so previews
    /// resolve at the neutral value.
    public var displayNumber: Int {
        switch self {
        case .fixed(let value): return Checklist.clampedMultiple(value)
        case .prompt: return 1
        }
    }

    /// True for `.prompt`.
    public var isPrompt: Bool {
        if case .prompt = self { return true }
        return false
    }

    /// This mode with its number clamped into `Checklist.multipleRange`, so the
    /// store never persists an out-of-range value and the no-op guard compares
    /// normalised values.
    public func clamped() -> Scaling {
        switch self {
        case .fixed(let value): return .fixed(Checklist.clampedMultiple(value))
        case .prompt(let lastFixed): return .prompt(lastFixed: Checklist.clampedMultiple(lastFixed))
        }
    }

    /// The other mode, carrying this mode's number: to Prompt keeps it as
    /// `lastFixed`; back to Fixed restores it. Drives the detail-view picker.
    public func toggled() -> Scaling {
        switch self {
        case .fixed(let value): return .prompt(lastFixed: Checklist.clampedMultiple(value))
        case .prompt(let lastFixed): return .fixed(Checklist.clampedMultiple(lastFixed))
        }
    }
}
```

In `Checklist`:

- Init (`:172-206`): replace `multiple: Int = 1,` with `scaling: Scaling = .fixed(1),`
  and `self.multiple = multiple` with `self.scaling = scaling`.
- Stored property (`:228-233`): replace

  ```swift
  public var multiple: Int
  ```

  with

  ```swift
  public var scaling: Scaling

  /// The legacy numeric view of `scaling`: the fixed factor, or a prompt's
  /// remembered default. Read-only compatibility accessor for the run funnel and
  /// display surfaces; write through `scaling` / `ChecklistStore.setScaling`.
  public var multiple: Int { scaling.number }
  ```

  Keep the existing doc-comment above `scaling`, updated to mention the mode.

- `CodingKeys` (`:266-268`): keep `multiple`, add `scalingMode`:

  ```swift
  case id, name, items, destinationListIdentifier, prefixesReminderNumbers, showsOnWatch, multiple, scalingMode, folderID, isArchived, archivedAt
  ```

- `init(from:)` (`:271-304`): replace the `multiple` decode with

  ```swift
  // Additive optional field: `multiple` stays the numeric shadow (a prompt's
  // last fixed value) so an older build keeps reading it. `scalingMode` is
  // additive too; absent or unknown reads as `.fixed(multiple)`. No version bump.
  let multiple = Checklist.clampedMultiple(
      try container.decodeIfPresent(Int.self, forKey: .multiple) ?? 1)
  let scaling: Scaling = (try container.decodeIfPresent(String.self, forKey: .scalingMode)) == "prompt"
      ? .prompt(lastFixed: multiple)
      : .fixed(multiple)
  ```

  and pass `scaling: scaling` in the `self = Checklist(...)` call.

- `encode(to:)` (`:306-336`): replace the single `multiple` encode with

  ```swift
  try container.encode(scaling.number, forKey: .multiple)
  try container.encode(scaling.isPrompt ? "prompt" : "fixed", forKey: .scalingMode)
  ```

- `ChecklistCodec.currentVersion` (`:564`): **unchanged at 5**.

#### 2. Store setter rename + copy paths

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

- `setMultiple(_:for:)` (`:388-402`) → `setScaling(_:for:)`:

  ```swift
  /// Sets a checklist's scaling mode and reports whether it applied. Clamps the
  /// carried number into `Checklist.multipleRange` first (defense in depth for
  /// imported/hand-edited payloads), then follows the no-op-guard shape: an
  /// unchanged mode never manufactures a spurious LWW win. Shares the checklist's
  /// coarse `revision`/`modifiedAt` clock.
  @discardableResult
  public func setScaling(_ newScaling: Scaling, for id: UUID) -> SetDestinationOutcome {
      guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
      let clamped = newScaling.clamped()
      guard checklists[index].scaling != clamped else { return .updated }
      checklists[index].scaling = clamped
      checklists[index].revision += 1
      checklists[index].modifiedAt = now()
      scheduleSave()
      return .updated
  }
  ```

- `duplicate(id:name:)` (`:260`): `multiple: source.multiple,` → `scaling: source.scaling,`
- `freshCopy(of:folderID:)` (`:285`): `multiple: checklist.multiple,` → `scaling: checklist.scaling,`

#### 3. LWW merge carries the mode

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistMerge.swift`
**Action**: modify

- `mergedChecklists` win set (`:143`): `merged.multiple = remoteChecklist.multiple` →
  `merged.scaling = remoteChecklist.scaling`.

#### 4. Consumers that need no source change (compile checks)

**Files**: `CheckStitchCore/.../ChecklistExport.swift`,
`CheckStitchCore/.../ChecklistReminders.swift`,
`CheckStitch/ContentView.swift`, `CheckStitch/ChecklistDetailView.swift`,
`CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: none

`ChecklistExport` serialises whole `Checklist` values (Codable), so it carries the
dual keys for free. `ChecklistReminders.create(from:targeting:gate:multipleOverride:)`
(`:26,34`) keeps `checklist.multiple` and its signature untouched. The three views
read `checklist.multiple` / `store.setMultiple` — the views read the computed
accessor, but see step 5: the *test* call sites and `ChecklistDetailView.multipleBinding`
are the only `setMultiple` callers.

Note: `ChecklistDetailView.multipleBinding` (`:311-315`) still sets through
`store.setMultiple`. Because the setter is renamed here, update that one call site
in Phase 0 to keep the build green, and Phase 1 replaces the binding entirely:

```swift
set: { store.setScaling(.fixed($0), for: checklistID) }
```

- `CheckStitchWidget/*` — no scaling references; no change.

#### 5. Test updates (mechanical, from the stored-property swap)

**Files**: `CheckStitchTests/ChecklistCodecTests.swift`,
`ChecklistExportTests.swift`, `ChecklistImportSessionTests.swift`,
`UbiquitousChecklistSyncTests.swift`, `ChecklistMergeTests.swift`,
`ChecklistStoreTests.swift`, `RunChecklistIntentTests.swift`,
`ChecklistRemindersTests.swift`, `ChecklistDetailViewTests.swift`
**Action**: modify

Mechanical replacements only (`.multiple` *reads* keep working through the
computed accessor; only `setMultiple` calls, mutating `x.multiple = n`
assignments, and `Checklist(multiple:)` constructions change):

| File / line | From | To |
| --- | --- | --- |
| `ChecklistCodecTests.swift:520,546` | `Checklist(multiple: 7)` / `(multiple: raw)` | `Checklist(scaling: .fixed(7))` / `(scaling: .fixed(raw))` |
| `ChecklistCodecTests.swift:525,548` | `.multiple == 7` / `decoded.multiple` | `.scaling == .fixed(7)` / `decoded.scaling.number` |
| `ChecklistExportTests.swift:102,117` | `Checklist(name:"Groceries", multiple: 7)` / `raw` | `scaling: .fixed(7)` / `.fixed(raw)` |
| `ChecklistImportSessionTests.swift:258,265` | `Checklist(name:"A", multiple:100)` / `(0)` | `scaling: .fixed(100)` / `.fixed(0)` |
| `UbiquitousChecklistSyncTests.swift:34` | `remoteChecklist.multiple = 7` | `remoteChecklist.scaling = .fixed(7)` |
| `ChecklistMergeTests.swift:1041,1043,1057,1059` | `.multiple = 7` / `= 1` | `.scaling = .fixed(7)` / `.fixed(1)` |
| `ChecklistStoreTests.swift:2152,2514,2528,2539` | `store.setMultiple(x, for:)` | `store.setScaling(.fixed(x), for:)` |
| `ChecklistStoreTests.swift:2588` | `Checklist(name:"Packing", multiple:4, …)` | `scaling: .fixed(4)` |
| `RunChecklistIntentTests.swift:268` | `store.setMultiple(3, for:)` | `store.setScaling(.fixed(3), for:)` |
| `ChecklistRemindersTests.swift:573,592` | `Checklist(… multiple: 2)` | `scaling: .fixed(2)` |
| `ChecklistDetailViewTests.swift:203` | `store.setMultiple(3, for:)` | `store.setScaling(.fixed(3), for:)` |

Add a new Swift Testing suite

**File**: `CheckStitchTests/ScalingTests.swift` (new)

```swift
@testable import CheckStitchCore
import Testing

struct ScalingTests {
    @Test(arguments: [(0, 1), (1, 1), (50, 50), (99, 99), (100, 99)])
    func numberClampsIntoTheSharedRange(_ raw: Int, _ expected: Int) {
        #expect(Scaling.fixed(raw).number == expected)
        #expect(Scaling.prompt(lastFixed: raw).number == expected)
    }

    @Test
    func toggledPreservesTheNumberAcrossModes() {
        #expect(Scaling.fixed(7).toggled() == .prompt(lastFixed: 7))
        #expect(Scaling.prompt(lastFixed: 7).toggled() == .fixed(7))
        #expect(Scaling.fixed(100).toggled() == .prompt(lastFixed: 99))
    }

    @Test
    func clampedNormalisesTheCarriedNumber() {
        #expect(Scaling.fixed(100).clamped() == .fixed(99))
        #expect(Scaling.prompt(lastFixed: 0).clamped() == .prompt(lastFixed: 1))
    }

    @Test
    func displayNumberIsNeutralForPrompt() {
        #expect(Scaling.fixed(7).displayNumber == 7)
        #expect(Scaling.prompt(lastFixed: 7).displayNumber == 1)
        #expect(Scaling.fixed(7).isPrompt == false)
        #expect(Scaling.prompt(lastFixed: 7).isPrompt == true)
    }
}
```

Add dual-key codec tests to `ChecklistCodecTests.swift` (legacy XCTest
`final class`, `@MainActor`):

```swift
/// Encode writes both keys: `multiple` (the numeric shadow) and `scalingMode`.
func testEncodeWritesBothScalingKeys() throws {
    let data = try ChecklistCodec.encode(ChecklistEnvelope(
        deviceID: "d", checklists: [Checklist(scaling: .prompt(lastFixed: 4))]))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let first = (json?["checklists"] as? [[String: Any]])?.first
    XCTAssertEqual(first?["multiple"] as? Int, 4)
    XCTAssertEqual(first?["scalingMode"] as? String, "prompt")
}

func testScalingRoundTripsBothModes() throws {
    for scaling in [Scaling.fixed(7), .prompt(lastFixed: 4)] {
        let data = try ChecklistCodec.encode(ChecklistEnvelope(
            deviceID: "d", checklists: [Checklist(scaling: scaling)]))
        XCTAssertEqual(ChecklistCodec.decode(data).first?.scaling, scaling)
    }
}

/// A payload with no `scalingMode` (an older build) reads as `.fixed(multiple)`.
func testLegacyPayloadWithoutScalingModeDecodesAsFixed() throws {
    let legacy = """
    {"version":5,"deviceID":"d","folders":[],"folderTombstones":[],"tombstones":[],
     "checklists":[{"id":"\(UUID().uuidString)","name":"A","items":[],"multiple":5,
     "modifiedAt":0,"revision":0,"itemOrder":[],"orderRevision":0,"orderModifiedAt":0}]}
    """
    let checklist = try XCTUnwrap(ChecklistCodec.decode(Data(legacy.utf8)).first)
    XCTAssertEqual(checklist.scaling, .fixed(5))
}

/// An unknown `scalingMode` token is forward-safe: it reads as `.fixed`.
func testUnknownScalingModeDecodesAsFixed() throws {
    // same payload shape with "scalingMode":"teleport", multiple 5 → .fixed(5)
}

func testCurrentVersionIsStillFive() {
    XCTAssertEqual(ChecklistCodec.currentVersion, 5)
}
```

(Paste the full JSON in the two payload tests; the `version: 5` and empty
tombstone/folder arrays are required by `ChecklistEnvelope`'s decoder.)

### Verification

#### Automated
- [x] `make test-unit` passes (`ScalingTests`, updated codec/store/merge/export/import suites)
- [x] `make build-mac` passes (macOS leg compiles against the renamed API)
- [x] `bash scripts/l10n-check.sh` still prints `l10n-check: ok` (no new keys yet)

#### Manual
- [ ] `git diff` shows `currentVersion` untouched and no `ChecklistCodec.classify` change
- [ ] A hand-saved payload containing `"multiple": 5` and no `scalingMode` still loads in the app as Scaling 5 (temporarily with `make run`; or trust the codec fixture)

---

## Phase 1: In-app Prompt scaling, end to end

**Goal**: picker replaces the always-visible number field; running a Prompt
checklist presents a validated sheet defaulting to `lastFixed`; confirming creates
reminders at the entered factor without touching stored state.

### Changes

#### 1. `PromptScalingSheet`

**File**: `CheckStitch/PromptScalingSheet.swift`
**Action**: create

```swift
import CheckStitchCore
import SwiftUI

/// Asks for the scaling factor for one Prompt-mode run. The entered number is
/// per-run: `onConfirm` hands it to the run's `multipleOverride` and nothing
/// here writes to the store. Confirm is disabled until the typed value is within
/// `Checklist.multipleRange`.
struct PromptScalingSheet: View {
    let lastFixed: Int
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(lastFixed: Int, onConfirm: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.lastFixed = lastFixed
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _text = State(initialValue: String(Checklist.clampedMultiple(lastFixed)))
    }

    /// The valid factor for the typed text, or `nil` when it is not an in-range
    /// integer. Pure so the suite pins the enable/disable rule without staging
    /// the sheet.
    static func validated(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              Checklist.multipleRange.contains(value)
        else { return nil }
        return value
    }

    private var enteredValue: Int? { Self.validated(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Scaling", text: $text)
                        .accessibilityIdentifier("promptScalingField")
                } footer: {
                    Text("Enter a number between 1 and 99.")
                }
            }
            .navigationTitle("Scale this run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .accessibilityIdentifier("promptScalingCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { if let enteredValue { onConfirm(enteredValue) } }
                        .disabled(enteredValue == nil)
                        .accessibilityIdentifier("promptScalingConfirmButton")
                }
            }
        }
    }
}
```

No `project.pbxproj` edit is needed (synchronized folder group).

#### 2. Run view model: park the run, forward the override

**File**: `CheckStitch/ChecklistRunViewModel.swift`
**Action**: modify

Add state next to `creating` (`:27-36`):

```swift
/// The checklist whose run is waiting for a Prompt-mode number; `nil` hides the
/// sheet. Never persisted.
private(set) var promptingRunID: UUID?

/// The checklist waiting for a Prompt-mode number, or `nil`. Drives the sheet.
var promptingChecklist: Checklist? {
    guard let promptingRunID else { return nil }
    return store.checklist(id: promptingRunID)
}
```

Add the two-step entry point and change the run signature:

```swift
/// Starts a run: `.fixed` runs immediately, `.prompt` parks the run behind the
/// scaling sheet. Never writes the mode or number back.
func startRun(for id: UUID) {
    guard !creating.contains(id),
          let checklist = store.checklist(id: id),
          checklist.hasRunnableItems
    else { return }
    if checklist.scaling.isPrompt {
        promptingRunID = id
    } else {
        Task { await createReminders(for: id) }
    }
}

/// Dismisses the scaling sheet without running.
func cancelPrompt() {
    promptingRunID = nil
}

/// Runs the parked checklist with the entered factor as a per-run override.
func confirmPrompt(multiple: Int) {
    guard let id = promptingRunID else { return }
    promptingRunID = nil
    Task { await createReminders(for: id, multipleOverride: multiple) }
}

/// Runs one checklist. `multipleOverride` is per-run only and never persisted.
func createReminders(for id: UUID, multipleOverride: Int? = nil) async {
    // existing guard + body unchanged …
    let outcome = await ChecklistReminders.create(
        from: checklist, targeting: targeting, gate: gate,
        multipleOverride: multipleOverride)
    // existing outcome switch unchanged …
}
```

#### 3. Detail view: mode picker + gated number field

**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Add at file scope (below the imports):

```swift
/// The two scaling modes as a `Hashable` picker selection. `Scaling` carries an
/// associated number, so the `Picker` tags on this value instead, mapping to and
/// from `Scaling` through `Scaling.toggled()`.
private enum ScalingMode: Hashable { case fixed, prompt }
```

Replace `multipleBinding(checklistID:)` (`:311-315`) with:

```swift
/// Per-selection write through the store for the scaling mode. Switching modes
/// keeps the current number (`Scaling.toggled()`); the getter reads the store so
/// a mode arriving over sync updates the picker. `.notFound` (deleted while this
/// screen was open) is ignored, matching `numberingBinding`.
private func scalingModeBinding(checklistID: UUID) -> Binding<ScalingMode> {
    Binding(
        get: { (store.checklist(id: checklistID)?.scaling.isPrompt ?? false) ? .prompt : .fixed },
        set: { mode in
            guard let current = store.checklist(id: checklistID)?.scaling else { return }
            let wantsPrompt = (mode == .prompt)
            guard wantsPrompt != current.isPrompt else { return }
            store.setScaling(current.toggled(), for: checklistID)
        }
    )
}

/// The fixed factor, read/written through the store. Only rendered for `.fixed`.
private func multipleBinding(checklistID: UUID) -> Binding<Int> {
    Binding(
        get: { store.checklist(id: checklistID)?.scaling.number ?? 1 },
        set: { store.setScaling(.fixed($0), for: checklistID) }
    )
}
```

Replace the Scaling `Section` (`:80-85`):

```swift
Section {
    Picker("Scaling", selection: scalingModeBinding(checklistID: checklistID)) {
        Text("Fixed").tag(ScalingMode.fixed)
        Text("Prompt").tag(ScalingMode.prompt)
    }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("checklistScalingModePicker")
    if store.checklist(id: checklistID)?.scaling.isPrompt != true {
        scalingField(checklistID: checklistID)
    }
} footer: {
    Text("Scaling multiplies any integer in double brackets — e.g. ((2)) becomes 6 at Scaling 3. The brackets are removed.")
}
```

`scalingField` (`:324-344`) is unchanged (it keeps its `#if os(iOS)` number-pad
branch and the `checklistScalingField` a11y id, and now renders only for `.fixed`).

#### 4. ContentView: route the run button + present the sheet

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- `createRemindersButton(for:)` (`:730`): `Task { await runVM.createReminders(for: id) }`
  → `runVM.startRun(for: id)`.
- Add a sheet in the modifier chain next to the paywall sheet (`:188-191`):

```swift
.sheet(item: Binding(get: { runVM.promptingChecklist },
                     set: { if $0 == nil { runVM.cancelPrompt() } })) { checklist in
    PromptScalingSheet(
        lastFixed: checklist.scaling.number,
        onConfirm: { runVM.confirmPrompt(multiple: $0) },
        onCancel: { runVM.cancelPrompt() })
}
```

#### 5. Localization keys

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add five App-catalog entries (six languages each, `"extractionState": "manual"`,
matching the existing `"Scaling"` entry shape at `:2915`):

| Key | de | es | fr | ja | zh-Hans |
| --- | --- | --- | --- | --- | --- |
| `Fixed` | `Fest` | `Fijo` | `Fixe` | `固定` | `固定` |
| `Prompt` | `Abfragen` | `Preguntar` | `Demander` | `入力を求める` | `提示输入` |
| `Confirm` | `Bestätigen` | `Confirmar` | `Confirmer` | `確認` | `确认` |
| `Scale this run` | `Diesen Durchlauf skalieren` | `Escalar esta ejecución` | `Mettre à l'échelle cette exécution` | `この実行を拡大` | `缩放此次运行` |
| `Enter a number between 1 and 99.` | `Gib eine Zahl zwischen 1 und 99 ein.` | `Introduce un número entre 1 y 99.` | `Saisis un nombre entre 1 et 99.` | `1 から 99 までの数字を入力してください。` | `请输入 1 到 99 之间的数字。` |

Entry template:

```json
"Fixed" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Fixed" } },
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Fest" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Fijo" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Fixe" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "固定" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "固定" } }
  }
}
```

(`LocalizationFixtures.requiredKeys` is updated in Phase 3.)

#### 6. Tests

**File**: `CheckStitchTests/PromptScalingSheetTests.swift` (new)

```swift
@testable import CheckStitch
import CheckStitchCore
import Testing

struct PromptScalingSheetTests {
    @Test(arguments: ["1", "2", "99", " 7 "])
    func validNumbersEnableConfirm(_ text: String) {
        #expect(PromptScalingSheet.validated(text) != nil)
    }

    @Test(arguments: ["", "0", "100", "-1", "2.5", "seven"])
    func invalidNumbersDisableConfirm(_ text: String) {
        #expect(PromptScalingSheet.validated(text) == nil)
    }

    @Test
    func validatedReturnsTheInRangeValue() {
        #expect(PromptScalingSheet.validated("42") == 42)
        #expect(PromptScalingSheet.validated("0") == nil)
        #expect(PromptScalingSheet.validated("100") == nil)
    }
}
```

**File**: `CheckStitchTests/ChecklistRunViewModelTests.swift`
**Action**: modify — add

```swift
@Test
func promptModeParksTheRunUntilConfirmed() async {
    let (store, id) = makeStore(items: ["milk ((2))"])
    store.setScaling(.prompt(lastFixed: 3), for: id)
    let spy = resolvableDestination()
    let viewModel = makeViewModel(store: store, targeting: spy)

    viewModel.startRun(for: id)
    #expect(viewModel.promptingRunID == id)
    #expect(spy.createdTitles.isEmpty, "nothing is created before confirming")

    viewModel.confirmPrompt(multiple: 5)
    await Task.yield() // let the spawned Task run
    // then await the run to completion via a second `createReminders`-free wait:
    // poll `viewModel.creating`/`created` or call the underlying await through a helper
    #expect(spy.createdTitles == ["milk 10"], "the entered factor scales the run")
    #expect(store.checklist(id: id)?.scaling == .prompt(lastFixed: 3),
            "the entered number is never persisted")
    #expect(store.checklist(id: id)?.multiple == 3)
}

@Test
func fixedModeRunsImmediatelyWithoutPrompting() async {
    let (store, id) = makeStore(items: ["milk ((2))"])
    store.setScaling(.fixed(3), for: id)
    let spy = resolvableDestination()
    let viewModel = makeViewModel(store: store, targeting: spy)

    viewModel.startRun(for: id)
    #expect(viewModel.promptingRunID == nil)
}

@Test
func cancelPromptDismissesWithoutRunning() async {
    let (store, id) = makeStore(items: ["milk ((2))"])
    store.setScaling(.prompt(lastFixed: 3), for: id)
    let spy = resolvableDestination()
    let viewModel = makeViewModel(store: store, targeting: spy)

    viewModel.startRun(for: id)
    viewModel.cancelPrompt()
    #expect(viewModel.promptingRunID == nil)
    #expect(spy.createdTitles.isEmpty)
}

@Test
func createRemindersForwardsTheOverrideWithoutPersisting() async {
    let (store, id) = makeStore(items: ["milk ((2))"])
    let spy = resolvableDestination()
    let viewModel = makeViewModel(store: store, targeting: spy)

    await viewModel.createReminders(for: id, multipleOverride: 5)

    #expect(spy.createdTitles == ["milk 10"])
    #expect(store.checklist(id: id)?.scaling == .fixed(1))
}
```

(`promptModeParksTheRunUntilConfirmed` spawns a detached `Task`; make the
assertion deterministic by extracting the run body — e.g. give the view model a
`func runNow(for:multipleOverride:) async` that `confirmPrompt` calls in a `Task`
— or by awaiting the same `Task` handle. Preferred: change `confirmPrompt` to
`@discardableResult func confirmPrompt(multiple: Int) -> Task<Void, Never>?`
returning the spawned task so the suite can `await` it. Keep `startRun`'s
`Task { await createReminders(for: id) }` likewise discardable.)

**File**: `CheckStitchTests/ChecklistRemindersTests.swift`
**Action**: modify — add an override-scaling case

```swift
@Test
func overrideScalesThisRunOnly() async {
    // existing `multiple: 2` fixture setup, then
    let outcome = await ChecklistReminders.create(
        from: checklist, targeting: spy, gate: unlockedGate, multipleOverride: 5)
    #expect(spy.createdTitles == /* markers × 5 */)
}
```

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `make build` passes (iOS leg compiles the new view)

#### Manual
- [ ] `make run`: open a checklist → Scaling shows a Fixed/Prompt segmented picker; pick Prompt → the number field disappears; pick Fixed → the previous number returns
- [ ] With Prompt selected and items containing `((2))`, tap the run button → a sheet appears, field defaults to the last fixed number, Confirm is disabled for empty/`0`/`100` and enabled for `3`
- [ ] Confirm with `3` → reminders are created with markers × 3; return to the detail view and confirm the picker still says Prompt and the remembered number is unchanged
- [ ] Cancel → no reminders created, no error alert
- [ ] Kill and relaunch the app → the checklist is still Prompt (mode persisted)

---

## Phase 2: App-Intent prompt (Siri / Shortcuts)

**Spike first (timeboxed, ~1 hour)** — front-loads design risk 6:

1. Implement steps 1 + 2 below with the fake-prompter tests, then run
   `make test-unit` (deterministic, no `requestValue`).
2. Implement step 3's `AppIntentScalingPrompter` and compile (`make build`).
   Verify by hand: (a) in Shortcuts, run a Prompt checklist with no `Multiple`
   argument → the system asks for a number, and the created reminders are scaled
   by it; (b) run a Prompt checklist from a widget button → observe what happens
   headless. If `requestValue` throws/is unavailable headless, the designed
   fallback (dialog, no reminders) is what ships — record the observed behaviour
   in the PR description.
3. If `requestValue` cannot be called at all in this configuration, stop and
   report; the design's fallback would need to become the primary intent
   behaviour (re-run `design`).

### Changes

#### 1. Prompting seam + production prompter

**File**: `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`
**Action**: modify

Add below the imports:

```swift
/// Test seam for resolving a Prompt-mode scaling number. The production
/// implementation asks through the intent's own optional `@Parameter`; suites
/// inject a fake so no system request machinery is needed.
@MainActor
protocol ScalingPrompting {
    func requestMultiple(prompt: LocalizedStringResource) async throws -> Int
}

/// Production prompter: asks the system for the `multiple` parameter's value.
@MainActor
struct AppIntentScalingPrompter: ScalingPrompting {
    let parameter: IntentParameter<Int?>

    func requestMultiple(prompt: LocalizedStringResource) async throws -> Int {
        // Spike confirms the exact `requestValue` overload and optionality; adapt
        // this guard if the SDK returns a non-optional.
        let value = try await parameter.requestValue(prompt)
        guard let value else { throw CancellationError() }
        return value
    }
}
```

#### 2. Intent injection + resolution order

**File**: `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`
**Action**: modify

- Add the stored seam next to `injectedRunState` (`:34-37`):
  `private let injectedPrompter: (any ScalingPrompting)?`
- `public init()` (`:39-44`): `self.injectedPrompter = nil`
- The test init (`:46-54`): drop `public`, add
  `prompter: (any ScalingPrompting)? = nil`, assign it. (No production caller uses
  the `store:` init — both `CheckStitch/Intents/CheckStitchShortcuts.swift:7` and
  the two widget callers use `RunChecklistIntent()`.)
- In `perform()`, after the `targeting.accessStatus()` switch (`:74-83`) and
  before `resolveGate()` (`:84`):

```swift
// Prompt mode with no explicit argument asks the system for a number. An
// explicit `multiple` always wins, preserving existing automations. A failure
// (headless automation, widget button, cancelled request) falls back to the
// existing dialog path and creates nothing.
var resolvedMultiple = multiple
if resolvedMultiple == nil, stored.scaling.isPrompt {
    let prompter: any ScalingPrompting =
        injectedPrompter ?? AppIntentScalingPrompter(parameter: $multiple)
    do {
        let requested = try await prompter.requestMultiple(prompt: RunChecklistDialogue.scalingPrompt)
        guard Checklist.multipleRange.contains(requested) else {
            throw RunChecklistIntentError.invalidMultiple
        }
        resolvedMultiple = requested
    } catch let error as RunChecklistIntentError {
        throw error
    } catch {
        return .result(dialog: IntentDialog(RunChecklistDialogue.scalingPromptUnavailable))
    }
}
```

- The create call (`:97-101`): `multipleOverride: multiple` → `multipleOverride: resolvedMultiple`.

#### 3. Dialogue strings

**File**: `CheckStitchCore/Sources/CheckStitchCore/RunChecklistIntent.swift`
**Action**: modify

Add to `RunChecklistDialogue` (`:111-143`):

```swift
static let scalingPrompt = LocalizedStringResource(
    "How many times should this scale?", table: "Localizable", bundle: .main)
static let scalingPromptUnavailable = LocalizedStringResource(
    "CheckStitch couldn't ask for a scaling number. Run the checklist in the app, or pass a Multiple value.",
    table: "Localizable", bundle: .main)
```

#### 4. Compile-only consumers

**Files**: `CheckStitch/Intents/CheckStitchShortcuts.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistConfigurationIntent.swift`
**Action**: none — verify they still compile (`make build`, `make watch-build`).

#### 5. Localization keys

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify — add two App-catalog entries (six languages each):

| Key | de | es | fr | ja | zh-Hans |
| --- | --- | --- | --- | --- | --- |
| `How many times should this scale?` | `Um wie viel soll dies skaliert werden?` | `¿Cuántas veces debe escalarse esto?` | `De combien faut-il mettre à l'échelle ?` | `何倍に拡大しますか？` | `应缩放多少倍？` |
| `CheckStitch couldn't ask for a scaling number. Run the checklist in the app, or pass a Multiple value.` | `CheckStitch konnte keine Skalierungszahl abfragen. Führe die Checkliste in der App aus oder übergib einen Wert für Mehrfaches.` | `CheckStitch no pudo pedir un número de escalado. Ejecuta la lista en la app o pasa un valor de Múltiplo.` | `CheckStitch n'a pas pu demander un nombre de mise à l'échelle. Lance la checklist dans l'app ou indique une valeur Multiple.` | `CheckStitch は拡大倍数を確認できませんでした。アプリでチェックリストを実行するか、倍数の値を指定してください。` | `CheckStitch 无法请求缩放倍数。请在 App 中运行清单，或传入倍数数值。` |

#### 6. Tests

**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify — add

```swift
/// Records Prompt-mode requests instead of touching the system request machinery.
@MainActor
final class FakeScalingPrompter: ScalingPrompting {
    var requestedPrompts: [LocalizedStringResource] = []
    var result: Result<Int, any Error> = .success(3)

    func requestMultiple(prompt: LocalizedStringResource) async throws -> Int {
        requestedPrompts.append(prompt)
        return try result.get()
    }
}
```

**File**: `CheckStitchTests/RunChecklistIntentTests.swift`
**Action**: modify — add

```swift
@Test
func promptModeAsksForANumberAndScalesByIt() async throws {
    let (store, id) = makeStore(items: ["Milk ((2))"])
    store.setScaling(.prompt(lastFixed: 3), for: id)
    let spy = resolvableDestination()
    let prompter = FakeScalingPrompter()
    prompter.result = .success(5)
    let intent = RunChecklistIntent(store: store, targeting: spy, gate: unlockedGate, prompter: prompter)
    intent.checklist = ChecklistEntity(id: id.uuidString, name: "Groceries")

    _ = try await intent.perform()

    #expect(prompter.requestedPrompts.count == 1)
    #expect(spy.createdTitles == ["Milk 10"])
    #expect(store.checklist(id: id)?.scaling == .prompt(lastFixed: 3),
            "the prompted number is never persisted")
}

@Test
func explicitMultipleSkipsThePrompt() async throws {
    let (store, id) = makeStore(items: ["Milk ((2))"])
    store.setScaling(.prompt(lastFixed: 3), for: id)
    let spy = resolvableDestination()
    let prompter = FakeScalingPrompter()
    let intent = RunChecklistIntent(store: store, targeting: spy, gate: unlockedGate, prompter: prompter)
    intent.checklist = ChecklistEntity(id: id.uuidString, name: "Groceries")
    intent.multiple = 4

    _ = try await intent.perform()

    #expect(prompter.requestedPrompts.isEmpty)
    #expect(spy.createdTitles == ["Milk 8"])
}

@Test
func fixedModeNeverPrompts() async throws {
    // .fixed(3) checklist, no `multiple`, fake prompter — expect no request, markers × 3
}

@Test
func failingPrompterReportsADialogAndCreatesNothing() async throws {
    // .prompt checklist, prompter.result = .failure(TestError.boom)
    // expect spy.createdTitles.isEmpty AND runState untouched (no beginRun)
}

@Test
func cancelledPrompterReportsADialogAndCreatesNothing() async throws {
    // prompter.result = .failure(CancellationError()) → same assertions
}

@Test
func outOfRangePromptedValueThrowsInvalidMultiple() async throws {
    // prompter.result = .success(100) → expect RunChecklistIntentError.invalidMultiple
}
```

### Verification

#### Automated
- [x] `make test-unit` passes with the injected prompter
- [x] `make build` and `make watch-build` pass
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`

#### Manual
- [ ] In Shortcuts, run a Prompt checklist with no `Multiple` → Siri/Shortcuts asks for a number; the created reminders use it
- [ ] In Shortcuts, pass `Multiple: 2` on a Prompt checklist → no prompt, markers × 2
- [ ] Run a Prompt checklist from a widget button → record the outcome in the PR description (expected: the designed fallback, no reminders, since widgets are headless)
- [ ] Run a Fixed checklist from Siri → behaves exactly as before

---

## Phase 3: Hardening, display polish, rollout

**Goal**: no misleading `×N` badge in Prompt mode; the watch shows an
un-multiplied title in Prompt mode; every new key is localized and pinned.

### Changes

#### 1. Badge suppressed for Prompt

**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

- `ItemRow` (`:389`): `let multiple: Int` → `let scaling: Scaling`
- Call site (`:100`): `multiple: checklist.multiple,` → `scaling: checklist.scaling,`
- Title/description resolution (`:423,442`): `multiple: multiple` → `multiple: scaling.number`
- Badge condition (`:428`): `if Self.showsScalingFactor(multiple)` → `if Self.showsScalingFactor(scaling)`
- Helper (`:469`):

```swift
/// The `×N` factor badge is only meaningful when scaling actually changes marker
/// text, so it is hidden at the neutral value and in Prompt mode.
static func showsScalingFactor(_ scaling: Scaling) -> Bool {
    if case .fixed(let value) = scaling { return value > 1 }
    return false
}
```

(Row marker text still resolves through `scaling.number`, matching today's
`multiple` behaviour — design decision 10 changes only the badge.)

#### 2. Watch resolves the neutral multiplier in Prompt mode

**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: modify

Replace both `current.multiple` resolutions (`:53,55`) with
`current.scaling.displayNumber`. (`Scaling.displayNumber` — Phase 0 — returns 1
for `.prompt` and the clamped factor for `.fixed`.)

#### 3. Test updates

**File**: `CheckStitchTests/ChecklistDetailViewTests.swift`
**Action**: modify

- `:163,179,257`: `ItemRow(… multiple: 1, …)` → `scaling: .fixed(1)`
- Badge test (`:189-193`):

```swift
@Test(arguments: [
    (Scaling.fixed(1), false),
    (Scaling.fixed(2), true),
    (Scaling.fixed(99), true),
    (Scaling.prompt(lastFixed: 3), false),
])
func scalingBadgeHiddenOnlyForNeutralOrPrompt(_ scaling: Scaling, _ visible: Bool) {
    #expect(ItemRow.showsScalingFactor(scaling) == visible)
}
```

(`Scaling.displayNumber`'s watch semantics are pinned by
`ScalingTests.displayNumberIsNeutralForPrompt` from Phase 0.)

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add all seven new App keys (Phase 1's five + Phase 2's two) to the `("App", [...])`
list in alphabetical position:

```
"CheckStitch couldn't ask for a scaling number. Run the checklist in the app, or pass a Multiple value.",
"Confirm",
"Enter a number between 1 and 99.",
"Fixed",
"How many times should this scale?",
"Prompt",
"Scale this run",
```

No Watch-catalog additions are needed (the watch has no scaling UI; the new keys
appear only in the App and intent surfaces).

### Verification

#### Automated
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make test-unit` passes (`ChecklistDetailViewTests`, `ScalingTests`, `LocalizationTests`)
- [x] `make build` passes
- [x] `./scripts/test.sh` prints `gate: ok` (sim build → sim test → `build-mac` → `watch-build` → `scripts/tests/run.sh` → shellcheck)

#### Manual
- [ ] `make run`: a Prompt checklist shows no `×N` badge; a Fixed checklist with 3 shows `×3`
- [ ] `bash scripts/run-devices.sh` (or `make run` on the watch leg): a Prompt checklist's watch rows show un-multiplied marker text and no badge
- [ ] Toggle to Prompt then back to Fixed on the device → the remembered number survives

---

## Testing Checkpoints

- **After Phase 0**: `make test-unit` green — `.fixed` behaves identically, the
  dual-key codec round-trips both modes, and a `scalingMode`-less payload decodes
  as `.fixed`. Nothing downstream broke.
- **After Phase 1**: `make test-unit` green; the manual `make run` prompt loop
  works and the entered number is not persisted.
- **After Phase 2**: `make test-unit` green with the injected prompter; the
  headless fallback is exercised by a test (`failingPrompter…`), not by hand.
- **After Phase 3**: `bash scripts/l10n-check.sh` and `./scripts/test.sh` print
  `gate: ok`; badge/watch display verified on the installed bundle.

---

## Deviations from `structure.md` (and why)

1. **`Scaling` is not `Codable`.** Structure listed `Codable`; the payload is two
   flat keys (`multiple` + `scalingMode`) handled in `Checklist`'s existing custom
   `Codable`, so a `Codable` conformance on the enum would imply a nested shape the
   wire format does not use. `Equatable, Hashable, Sendable` is what's required
   (`Checklist: Hashable`).
2. **`Scaling.clamped()` is an instance method, not `static func clamped(_:) -> Int`.**
   The store needs the mode preserved alongside the clamped number; a static
   `Int`-only helper would be unused (Periphery-visible). `Scaling.number` still
   routes every read through `Checklist.clampedMultiple`, so the single clamp
   source is intact.
3. **Two extra `Scaling` members** — `displayNumber` (used by the watch in Phase 3
   and unit-testable from `CheckStitchTests`, since the Watch view itself has no
   test target) and `toggled()` (used by the detail-view picker binding and
   testable). Structure's "watch detail test" is not achievable: there is no Watch
   test target — `WatchChecklistStoreTests` tests Core types, not the view.
4. **`ChecklistDetailView.multipleBinding` is touched in Phase 0** (one line) so the
   branch compiles after the setter rename; Phase 1 replaces it.
5. **`CheckStitchWidget` is untouched.** Both widget buttons build
   `RunChecklistIntent()` with no `multiple`, so a Prompt checklist run from a
   widget attempts `requestValue` headless. Per design decision 6 the fallback
   dialog is the designed behaviour; Phase 2's spike records what actually happens.
   If that is an unacceptable silent no-op, the one-line remedy is for the two
   widget callers to set `intent.multiple = <checklist>.multiple` (explicit wins) —
   a design decision to take separately, not added here.
6. **`ScalingTests.swift` and `PromptScalingSheetTests.swift` are new files**
   not named in structure; they carry the behaviour structure attributed to
   `ChecklistDetailViewTests` (the picker/field gating can't be staged headlessly —
   only view *values* are inspectable, per the existing suite's own doc comment).
