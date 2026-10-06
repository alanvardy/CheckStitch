# Implementation Plan

## Overview

Add a Shortcuts.app **Create Checklist** App Intent (`name: String` + `items: [String]`)
that writes a *stored* checklist into `ChecklistStore` in a single save, plus
`ChecklistStore.reconcileFromDefaults()` called from `MyApp`'s `scenePhase == .active`
so a running backgrounded app folds in (and cannot clobber) the intent's write.
No Reminders, no run, no purchase gate.

**Binding decisions** come from VAR-1116's "Decisions" (1–12) and "Implementation
notes". Recon findings that shape the plan:

- The intent's sibling `RunChecklistIntent` declares `static let title` and
  `parameterSummary` as plain literals and does **not** register them in
  `Localizable.xcstrings`; only its **dialogue/error** strings are in the **App**
  catalog (`CheckStitch/Localizable.xcstrings`, `bundle: .main`), not the Core
  catalog. The new intent follows that split: title/summary/parameter titles are
  literals; the 4 dialogue/error strings get App-catalog keys.
- `ChecklistStoreTests` is a legacy **XCTest** suite (`func test…`), unlike the
  Swift Testing intent suites. Store tests are appended there; the new intent
  suite is a Swift Testing `struct`.
- `ChecklistStore` has no reconcile precedent — `reconcileFromDefaults()` reuses
  the existing `apply(remote:)` / `ChecklistMerge` seam (which already suppresses
  `onChange` via `isApplyingRemote`), then fires `onChange` once explicitly.
- `ChecklistCodec.currentVersion` is 5; `ChecklistEnvelope` is `Equatable`.

## Two compile-verify-first unknowns (ticket)

- **(a)** Does `@Parameter var items: [String]` compile and render as a
  Shortcuts list? Fallback: a single multiline `String` split on newline + comma.
- **(b)** Is an App Intents metadata entry emitted for a `CheckStitchCore`-declared
  intent that no `AppShortcutsProvider` references? `CheckStitchShortcuts` is an
  `AppShortcutsProvider` (it already exists — **do not modify it**), so the
  metadata phase runs. If the action does not appear in Shortcuts.app, the
  fallback is to move **only** `CreateChecklistIntent`, `CreateChecklistIntentError`
  and `CreateChecklistDialogue` into `CheckStitch/Intents/CreateChecklistIntent.swift`
  (app target) — the store method stays in Core, and the intent test already
  imports both modules.

---

## Phase 1: Create Checklist intent → one stored checklist (single save)

**Outcome:** running the action from Shortcuts.app stores a named checklist with
all its items in one write; blank name and empty-items are rejected with typed
errors; the exact success/error text is unit-testable. Resolves unknown (a);
verifies unknown (b).

### Changes

#### 1. Store entry point

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify — add directly beside `create(name:)` (around line 209).

```swift
/// Creates a checklist with a caller-supplied name and one title-only item per
/// entry, in a single `save()`/single `onChange` — the Create Checklist intent
/// must not save N times. The name is disambiguated by `uniqueName` exactly as
/// `create(name:)`. Callers pass a non-blank name and non-blank titles; the
/// intent normalises and validates before calling.
@discardableResult
public func create(name: String, itemTitles: [String]) -> Checklist {
    let items = itemTitles.map { ChecklistItem(title: $0, modifiedAt: now(), revision: 1) }
    let checklist = Checklist(
        name: Self.uniqueName(basedOn: name, taken: activeNames),
        items: items,
        modifiedAt: now(),
        revision: 1)
    checklists.append(checklist)
    save()
    return checklist
}
```

`Checklist`'s defaults already give `folderID nil`, `multiple 1`,
`prefixesReminderNumbers false`, `showsOnWatch true`, `destinationListIdentifier nil`,
`itemOrder = items.map(\.id)`; the items match `addItem(to:title:)`'s shape
(`title` only, `modifiedAt: now()`, `revision: 1`).

#### 2. Intent, error and dialogue

**File**: `CheckStitchCore/Sources/CheckStitchCore/CreateChecklistIntent.swift`
**Action**: create (no `project.pbxproj` edit needed — `CheckStitchCore` is a
synchronized package; do **not** touch `CheckStitch/Intents/CheckStitchShortcuts.swift`).

```swift
import AppIntents

/// Thrown when the caller supplies a blank name or no surviving items.
enum CreateChecklistIntentError: LocalizedError {
    case blankName
    case noItems
    var errorDescription: String? {
        switch self {
        case .blankName:
            LocalizedStringResource("Give the checklist a name.", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
        case .noItems:
            LocalizedStringResource("Add at least one item.", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
        }
    }
}

public struct CreateChecklistIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Checklist"
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Name")
    public var name: String

    @Parameter(title: "Items")
    public var items: [String]

    // test seam; nil → fresh production store
    private let injectedStore: ChecklistStore?

    public init() { self.injectedStore = nil }

    @MainActor
    public init(store: ChecklistStore) { self.injectedStore = store }

    public static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$name) with \(\.$items)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = injectedStore ?? ChecklistStore(defaults: AppGroup.defaults)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CreateChecklistIntentError.blankName }
        let titles = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { throw CreateChecklistIntentError.noItems }
        let checklist = store.create(name: trimmedName, itemTitles: titles)
        return .result(dialog: IntentDialog(
            CreateChecklistDialogue.message(name: checklist.name, itemCount: checklist.items.count)))
    }
}

/// Outcome→speech mapping, next to the intent so exact text is unit-testable.
/// Keys are in the App catalog.
enum CreateChecklistDialogue {
    @MainActor
    static func message(name: String, itemCount: Int) -> LocalizedStringResource {
        guard itemCount != 1 else {
            return LocalizedStringResource(
                "Created \(name) with 1 item.", table: "Localizable", bundle: .main)
        }
        return LocalizedStringResource(
            "Created \(name) with \(itemCount) items.", table: "Localizable", bundle: .main)
    }
}
```

The success dialog reports the **actual disambiguated** `checklist.name`, not the
input name. `Int` interpolation generates `%lld`; the catalog keys are therefore
`"Created %@ with %lld items."` and `"Created %@ with 1 item."`.

#### 3. Localization

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify — insert 4 new entries into the `localizations` object
(keys are catalogued in the **App** catalog because the intent uses `bundle: .main`,
matching `RunChecklistIntent`). Use the `edit` skill's small-anchor rule; do not
paste whole entries. Existing entry template (copy this shape exactly):

```json
    "Created %@ with %lld items." : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Created %@ with %lld items." } },
        "de" : { "stringUnit" : { "state" : "translated", "value" : "%@ mit %lld Elementen erstellt." } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Se creó %@ con %lld elementos." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "%@ créée avec %lld éléments." } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "%@を%lld個の項目で作成しました。" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "已创建%@，包含%lld个项目。" } }
      }
    },
```

The other three (`"Created %@ with 1 item."`, `"Give the checklist a name."`,
`"Add at least one item."`) use the identical full structure (one `localizations`
object with all six languages, `"extractionState" : "manual"`). Draft values:

| key | de | es | fr | ja | zh-Hans |
|---|---|---|---|---|---|
| `Created %@ with 1 item.` | `%@ mit 1 Element erstellt.` | `Se creó %@ con 1 elemento.` | `%@ créée avec 1 élément.` | `%@を1個の項目で作成しました。` | `已创建%@，包含1个项目。` |
| `Give the checklist a name.` | `Gib der Checkliste einen Namen.` | `Dale un nombre a la lista.` | `Donnez un nom à la liste.` | `チェックリストに名前を付けてください。` | `请为清单命名。` |
| `Add at least one item.` | `Füge mindestens ein Element hinzu.` | `Añade al menos un elemento.` | `Ajoutez au moins un élément.` | `少なくとも1つの項目を追加してください。` | `请至少添加一个项目。` |

Run `bash scripts/l10n-check.sh` first (fast, no build) — it fails if any language
is missing or if a non-English value is byte-identical to English.

#### 4. Localization fixture

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify — add the 4 keys to the `("App", [ … ])` array in
`requiredKeys` (near the other intent-dialogue keys, e.g. after
`"Created 1 reminder for %@.",`):

```swift
            "Created %@ with %lld items.",
            "Created %@ with 1 item.",
            "Give the checklist a name.",
            "Add at least one item.",
```

`"Name"` and `"Items"` are already required App keys (parameter titles), so no
new catalog entry is needed for them. `"Create Checklist"` /
`"Create %@ with %@"` are deliberately **not** catalogued, mirroring
`RunChecklistIntent`'s title/summary.

#### 5. Store tests

**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify — append XCTest methods using the existing
`makeDefaults()` / `makeStore(defaults:)` helpers. Cover:

```swift
func testCreateWithItemTitlesKeepsInputOrderAndTitleOnlyShape() { … }
// create(name: "Groceries", itemTitles: ["Milk", "milk", "Eggs"]) →
// one checklist, items titles == ["Milk", "milk", "Eggs"] (no dedup),
// each item description == "", relativeDate == nil, priority == .none,
// checklist.multiple == 1, folderID == nil, showsOnWatch == true.

func testCreateWithItemTitlesSavesExactlyOnce() { … }
// store.onChange = { count += 1 }; create(name:itemTitles:) with 3 titles →
// count == 1 and reloading a fresh store from the same defaults sees all 3 items.

func testCreateWithItemTitlesDisambiguatesName() throws { … }
// store.create(name: "Groceries"); store.create(name: "Groceries", itemTitles: ["Milk"])
// → names ["Groceries", "Groceries 2"]; also " groceries " → "Groceries 2"
// (case/trim-insensitive, via uniqueName).
```

#### 6. Intent tests

**File**: `CheckStitchTests/CreateChecklistIntentTests.swift`
**Action**: create — Swift Testing, `@MainActor struct`, isolated defaults,
injected-store seam. Mirror `RunChecklistIntentTests` naming (no `test` prefix):

```swift
@testable import CheckStitch
@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct CreateChecklistIntentTests {
    private func makeIntent() -> (intent: CreateChecklistIntent, store: ChecklistStore) {
        let store = ChecklistStore(defaults: makeIsolatedDefaults())
        return (CreateChecklistIntent(store: store), store)
    }
    // createStoresOneItemAndReportsExactDialogue
    //   intent.name = "Groceries"; intent.items = ["Milk"]; perform()
    //   → store has "Groceries" with items ["Milk"]
    //   → CreateChecklistDialogue.message(name: "Groceries", itemCount: 1).resolved()
    //      == "Created Groceries with 1 item."
    // createStoresManyItemsAndReportsCount
    //   items = ["Milk", "Eggs", "  Bread  "] → 3 items, dialogue
    //   "Created Groceries with 3 items."  (whitespace trimmed)
    // duplicateNameIsDisambiguatedAndDialogueReportsActualName
    //   store.create(name: "Groceries") first; perform() name "Groceries"
    //   → store names ["Groceries", "Groceries 2"]
    //   → dialogue == "Created Groceries 2 with 1 item."
    // blankNameThrowsAndCreatesNothing
    //   name "   " → catch CreateChecklistIntentError → errorDescription == "Give the checklist a name."
    //   → store.checklists.isEmpty
    // blankOnlyItemsThrowAndCreateNothing
    //   items ["", "   ", "\n"] → errorDescription == "Add at least one item."
    //   → store.checklists.isEmpty
    // emptyItemsThrowAndCreateNothing
    //   items [] → same as above
    // performReadsInjectedStoreNotTheAppGroup
    //   injected store sees the new checklist; no write to AppGroup.defaults.
}
```

Use the existing error-assertion shape (from `RunChecklistIntentTests`):

```swift
do {
    _ = try await intent.perform()
    Issue.record("a blank name should throw, not perform")
} catch let error as CreateChecklistIntentError {
    #expect(error.errorDescription == "Give the checklist a name.")
} catch {
    Issue.record("unexpected error type: \(error)")
}
```

### Verification

#### Automated
- [x] `bash scripts/l10n-check.sh` passes (4 new keys × 6 languages, non-English differs)
- [x] `make test-unit` passes (new store XCTest methods + `CreateChecklistIntentTests`)
- [x] `make build` compiles `@Parameter var items: [String]` (unknown (a) confirmed; else apply the multiline-`String` fallback and update the tests)
- [x] App Intents metadata contains `CreateChecklistIntent` — inspect the built product after `make build` (e.g. `grep -R CreateChecklistIntent` over the product's App Intents metadata / `strings` it); unknown (b) bad → move the intent type into the app target

#### Manual
- [ ] `make build-mac-signed`, open macOS Shortcuts.app, confirm a **Create Checklist** action exists with Name + Items (list) fields and summary "Create (Name) with (Items)"

---

## Phase 2: Backgrounded app folds in the intent's write

**Outcome:** if CheckStitch is alive and backgrounded when the shortcut writes a
checklist through a fresh store, returning to `.active` shows the new checklist
and the app's next save cannot clobber it. Idempotent on cold launch;
suppressed when the stored payload is from a newer app version.

### Changes

#### 1. Store reconcile entry point

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify — add beside `apply(remote:)` (around line 679).

```swift
/// Re-reads the App Group payload and folds any externally written state
/// (the Create Checklist intent writes through a fresh store) into memory.
/// Called on every return to `.active`. Idempotent on a cold launch, where
/// `init` already read the same payload. `apply(remote:)` suppresses `onChange`;
/// fire it once explicitly when state actually changed so the iCloud push rides
/// the change (the watch push rides the SwiftUI `checklists` change).
@discardableResult
public func reconcileFromDefaults() -> Bool {
    guard canOverwriteStoredPayload else { return false }
    defaults.synchronize()   // a cross-process App Group write may not be visible yet
    guard let data = defaults.data(forKey: key),
          case .loaded(let remote) = ChecklistCodec.classify(data)
    else { return false }
    let before = envelope
    apply(remote: remote)
    guard envelope != before else { return false }
    onChange?()
    return true
}
```

Only `.loaded` (current-version) payloads are folded in; a legacy `.migratable`
write is not expected (the intent's fresh store always encodes the current
version). `apply(remote:)` already re-guards `canOverwriteStoredPayload` and
`remote.version == currentVersion`.

#### 2. Scene-phase hook (iOS + macOS)

**File**: `CheckStitch/MyApp.swift`
**Action**: modify — both `.onChange(of: scenePhase)` blocks (macOS ~line 86,
iOS ~line 112). Restructure to an if/else:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .active {
        // Fold in a checklist written by the Create Checklist intent while
        // CheckStitch was backgrounded, before any edit can clobber it.
        store.reconcileFromDefaults()
    } else {
        // Flush coalesced text edits and push before the app suspends.
        store.flushPendingSave()
        syncService.pushNow()
    }
}
```

#### 3. Reconcile tests

**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify — append XCTest methods (reuse `makeDefaults()` /
`makeStore(defaults:)` and the file's `key` constant):

```swift
func testReconcileFoldsInExternalAppGroupWrite() throws { … }
// store A on empty defaults, onChange counter = 0.
// Write an envelope for a *different* deviceID with a "From Intent" checklist
// directly to defaults via ChecklistCodec.encode(ChecklistEnvelope(...)).
// reconcileFromDefaults() == true; store contains "From Intent";
// onChange fired exactly once.

func testReconcileIsIdempotentOnColdLaunch() throws { … }
// Write an envelope, then makeStore(defaults:) (init already loaded it),
// onChange counter = 0. reconcileFromDefaults() == false; count == 0;
// checklist list unchanged.

func testReconcileRefusesNewerStoredPayload() throws { … }
// Write an envelope with version ChecklistCodec.currentVersion + 1.
// store.canAcceptRemoteChanges == false; reconcileFromDefaults() == false.
```


### Verification

#### Automated
- [x] `make test-unit` passes (new reconcile methods + everything from Phase 1)
- [x] `./scripts/test.sh` prints `gate: ok` (adds `make build-mac`, `make watch-build`, shell checks)

#### Manual
- [ ] `make build-mac-signed` / `scripts/run-devices.sh`; in Shortcuts.app run Create Checklist while the app is backgrounded; return to the app and confirm the checklist is listed with its items and survives a subsequent edit. Re-run with a duplicate name (expect "… 2"), blank name (expect "Give the checklist a name."), and no items (expect "Add at least one item.")
- [ ] Confirm the created checklist reaches the watch/widget after returning to `.active`
