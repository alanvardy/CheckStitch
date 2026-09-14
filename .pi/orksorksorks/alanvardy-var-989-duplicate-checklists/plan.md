# Implementation Plan

## Overview

Add a **Duplicate Checklist** button to the edit-checklist screen, sitting
between "Add Item" and the destructive "Remove Checklist" in that screen's
trailing `Section`. It raises an input alert (SwiftUI `.alert` with a
`TextField`) that asks for the copy's name, prefilled with
`"<original name> copy"`; confirming creates a copy whose items are all fresh
`ChecklistItem`s (new `UUID`, revision 1) and whose name is disambiguated by the
existing `uniqueName` machinery, appended and persisted through the store's
normal `save()` → `onChange` sync path.

Three commits, in dependency order: store behaviour → view surface →
localization. No schema/envelope change (stays version 2), no tombstones, no
EventKit, no entitlement, no `project.pbxproj` edit.

### Resolved decisions (recon-derived)

- **The `" copy"` suffix is a plain literal, not a localized format key.**
  `uniqueName` (`CheckStitch/ChecklistStore.swift:93`) is pure string
  interpolation (`"\(base) \(suffix)"`) and is shared with `create`/`rename`;
  `medium.md` mandates reusing that machinery. So `medium.md`'s hedge about an
  `"<original> copy"` format key resolves to **no format key** — only the new
  UI strings are localized. Consequence: a non-English user sees
  `"Groceries copy 2"` untranslated. Localizing it would mean editing shared
  naming code and existing `create`/`rename` behaviour — out of scope.
- **A taken name is silently disambiguated, never alerted.** `create(name:)`
  documents that "creation therefore always succeeds", so typing a name another
  checklist owns yields `"<name> 2"` rather than the rename path's
  `isNameConflictPresented` alert. Only `rename` reports conflicts.
- **The copy is appended at the end**, matching `create(name:)`; it is not
  inserted next to the source and the screen does not navigate to it.
- **A blank name falls back to the default** (`"<original> copy"`), so clearing
  the alert's text field can never create a checklist named `""`.
- **`ChecklistStore` lives in the app target** (it `import CheckStitchCore` for
  the models), so both suites keep `@testable import CheckStitch` — not the
  `@testable import CheckStitchCore` used by full-Core suites.

## Phase 1: Store — duplicate with fresh identifiers and names

### Changes

#### 1. `duplicateName(basedOn:)` + `duplicate(id:name:)`

**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify — add after `create(name:)` (ends line 78), before `rename`.

The suffix literal lives in exactly one place, and `duplicate` reuses the same
`uniqueName`/`ChecklistItem` defaults that `create`/`addItem` already use, then
calls `save()` (which fires `onChange` unless `isApplyingRemote`, line 216).

```swift
    /// The name a duplicate is offered by default: the source name plus a
    /// literal " copy", left for `uniqueName` to disambiguate on commit — a
    /// second copy of "Groceries" is therefore offered as "Groceries copy 2".
    static func duplicateName(basedOn sourceName: String) -> String {
        "\(sourceName) copy"
    }

    /// Duplicates a checklist: every item is copied into a fresh `ChecklistItem`
    /// (new `UUID`, revision 1), under a name disambiguated by the same
    /// machinery `create` uses, so a duplicate always succeeds. Returns `nil`
    /// when the source no longer exists, mirroring `delete(id:)`'s silent
    /// no-op. A blank name falls back to the offered default.
    @discardableResult
    func duplicate(id: UUID, name: String) -> Checklist? {
        guard let source = checklists.first(where: { $0.id == id }) else { return nil }
        let requested = name.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty
            ? Self.duplicateName(basedOn: source.name)
            : name
        let copy = Checklist(
            name: Self.uniqueName(basedOn: requested, taken: checklists.map(\.name)),
            items: source.items.map { ChecklistItem(title: $0.title, modifiedAt: now(), revision: 1) },
            modifiedAt: now(),
            revision: 1
        )
        checklists.append(copy)
        save()
        return copy
    }
```

No other store change: the envelope stays version 2, no tombstone is written,
and `save()` already drives the KVS sync path.

#### 2. Store tests

**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify — add cases to the XCTest `@MainActor final class
ChecklistStoreTests`. Follow the existing per-test shape exactly:
`let suite = makeDefaults(); defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }; let store = makeStore(defaults: suite.defaults)`.

```swift
    func testDuplicateCopiesItemsWithFreshIdentifiersAndRevisions() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let store = makeStore(defaults: suite.defaults)

        let source = store.create(name: "Groceries")
        store.addItem(to: source.id)
        let item = store.checklist(id: source.id)?.items.first
        store.updateItem(checklistID: source.id, itemID: item?.id ?? UUID(), title: "Milk")

        let copy = store.duplicate(id: source.id, name: ChecklistStore.duplicateName(basedOn: "Groceries"))

        let duplicated = try? XCTUnwrap(copy)
        XCTAssertEqual(duplicated?.items.map(\.title), ["Milk"])
        XCTAssertEqual(duplicated?.revision, 1)
        XCTAssertEqual(duplicated?.items.first?.revision, 1)          // fresh, not the source's 2
        XCTAssertNotEqual(duplicated?.items.first?.id, item?.id)      // never a reused id
        XCTAssertNotEqual(duplicated?.id, source.id)
        XCTAssertEqual(store.checklist(id: source.id)?.items.first?.revision, 2)  // source untouched
    }

    func testDuplicateDisambiguatesTheCopyName() {
        // "Groceries copy", "Groceries copy 2", "Groceries copy 3"
        // and a user-typed taken name -> "Groceries 2"
    }

    func testDuplicateNameIsSourceNamePlusCopy() {
        XCTAssertEqual(ChecklistStore.duplicateName(basedOn: "Groceries"), "Groceries copy")
    }

    func testDuplicateBlankNameFallsBackToTheDefault() {
        // duplicate(id:name: "   ") -> name "Groceries copy", never ""
    }

    func testDuplicatePersistsAcrossReload() {
        // duplicate, then a fresh makeStore(defaults:) sees the copy and its items
    }

    func testDuplicateFiresOnChange() {
        // mirrors testOnChangeFiresForLocalSavesButNotWhenApplyingRemote (line 346)
    }

    func testDuplicateIgnoresAnUnknownID() {
        // duplicate(id: UUID(), name: "x") returns nil, checklists unchanged, onChange not fired
    }
```

Notes: use the `Clock` class (line 27) via the `now:` store variant only if a
timestamp assertion is added — the assertions above need `textEditDelay: nil`
(covers the debounced `updateItem`) but not the clock. `addItem` yields revision
1 and `updateItem` bumps it to 2 (`ChecklistStoreTests.swift:361-367`), which is
what makes the "fresh revision 1" assertion exact.

### Verification

#### Automated
- [x] `make test-unit` passes, including all new `ChecklistStoreTests` cases

#### Manual
- [ ] Read the diff: `checklists` envelope version is still 2, no tombstone
      path added, `uniqueName` and `save()` untouched

---

## Phase 2: View — the button and its name alert

### Changes

#### 1. State slots + button + alert

**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify — three disjoint edits.

(a) New state below `isNameConflictPresented` (line 22):

```swift
    /// The duplicate flow asks for the copy's name first, so the button only
    /// raises this alert and never creates anything itself.
    @State private var isDuplicatePresented = false
    /// Buffered copy name for that alert, seeded from the source name when the
    /// alert is raised.
    @State private var duplicateDraftName = ""
```

(b) The button, **between** "Add Item" and the destructive "Remove Checklist",
using the same `Button`/`Label`/`.accessibilityIdentifier`/`.checkStitchButton()`
idiom as its neighbours (no `role: .destructive` — duplication is additive):

```swift
                    Button {
                        duplicateDraftName = ChecklistStore.duplicateName(basedOn: checklist.name)
                        isDuplicatePresented = true
                    } label: {
                        Label("Duplicate Checklist", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("duplicateChecklistButton")
                    .checkStitchButton()
```

(c) The alert, attached to the `Form` next to the existing `.alert("Name
already in use", ...)` (line ~85). Multiple `.alert` modifiers on one view are
supported on this toolchain (iOS 27 / Xcode 26.6):

```swift
            .alert("Duplicate Checklist", isPresented: $isDuplicatePresented) {
                TextField("Name", text: $duplicateDraftName)
                    .accessibilityIdentifier("duplicateChecklistNameField")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("cancelDuplicateChecklistButton")
                Button("Duplicate") {
                    store.duplicate(id: checklistID, name: duplicateDraftName)
                }
                .accessibilityIdentifier("confirmDuplicateChecklistButton")
            } message: {
                Text("Creates a copy with the same items.")
            }
```

`checklist` is already bound in-scope by `if let checklist = store.checklist(id: checklistID)`,
so the prefill needs no extra store lookup. The result is discarded — the screen
stays on the original checklist; the copy appears in the list via `onChange`.

#### 2. View test

**File**: `CheckStitchTests/ChecklistDetailViewTests.swift`
**Action**: modify — add one Swift Testing case. The suite's technique is
pinning *stored state slots* on the view value (`String(describing:)`); it
cannot inspect the body or a direct store call, so the alert's two new slots are
what a test can pin.

```swift
    /// Duplicating is a two-step flow: the button only raises a name alert with
    /// its own draft, so nothing is created until the user confirms a name.
    @Test
    func duplicateChecklistIsGatedBehindANameAlert() {
        let described = String(describing: ChecklistDetailView(checklistID: UUID()))
        #expect(described.contains("isDuplicatePresented"))
        #expect(described.contains("duplicateDraftName"))
    }
```

Also widen the file's header doc comment (currently "Pins the
destructive-remove wiring of the checklist detail screen.") to mention the
duplicate flow, so the header stays accurate.

### Verification

#### Automated
- [x] `make test-unit` passes, including the new `ChecklistDetailViewTests` case
- [x] `make build` passes (the view is shared by iOS and macOS)

#### Manual
- [ ] `make run` on the simulator, open a checklist with items: the trailing
      section reads Add Item / **Duplicate Checklist** / Remove Checklist, with
      Remove still last and still destructive-styled
- [ ] Tap Duplicate Checklist: an alert titled "Duplicate Checklist" appears
      with the name field prefilled `"<original name> copy"`, Cancel and
      Duplicate buttons
- [ ] Confirm with the prefill: the list screen shows a new `"… copy"` entry
      holding the same item titles; the original is unchanged
- [ ] Duplicate the same checklist again and accept the prefill: the new entry
      is `"<original> copy 2"` (the prefill is re-disambiguated on commit)
- [ ] Cancel: no new checklist is created
- [ ] `make build-mac-signed` then launch the macOS app and repeat one
      duplicate to confirm the shared view renders the button and alert there

---

## Phase 3: Localization — catalog and fixtures

### Changes

#### 1. Catalog entries

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify — add three key blocks, each in **alphabetical** position,
with `extractionState: "manual"` and all six languages (`en`, `de`, `es`,
`fr`, `ja`, `zh-Hans`) as `stringUnit` / `state: "translated"`, matching the
"Remove Checklist" block shape at line 1193.

| Key | Insert before | Non-English values |
| --- | --- | --- |
| `Creates a copy with the same items.` | `"Dark"` (line 537) | de `Erstellt eine Kopie mit denselben Einträgen.` · es `Crea una copia con los mismos elementos.` · fr `Crée une copie avec les mêmes éléments.` · ja `同じ項目のコピーを作成します。` · zh-Hans `创建包含相同项目的副本。` |
| `Duplicate` | `"Edit checklist"` (line 619) | de `Duplizieren` · es `Duplicar` · fr `Dupliquer` · ja `複製` · zh-Hans `复制` |
| `Duplicate Checklist` | `"Edit checklist"` (line 619), after `Duplicate` | de `Checkliste duplizieren` · es `Duplicar lista` · fr `Dupliquer la liste` · ja `チェックリストを複製` · zh-Hans `复制清单` |

Every non-English value differs from English, so no `excludedIdentities` entry
is needed. `en` values are the keys themselves. `"Name"` and `"Cancel"` are
reused by the alert and already exist — do not re-add them.

#### 2. Fixture

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify — extend the `("App", [...])` `requiredKeys` array, keeping
it alphabetical:

```swift
            "Create reminders from checklist",
            "Creates a copy with the same items.",
            "Dark",
            "Done",
            "Duplicate",
            "Duplicate Checklist",
            "Edit checklist",
```

`LocalizationTests.swift` needs no change: it auto-verifies presence and the
non-English-differs canary from these fixtures.

### Verification

#### Automated
- [x] `make test-unit` passes, including `LocalizationTests` presence and
      non-English-differs checks for the three new keys
- [x] `make build` passes

#### Manual
- [ ] Open the alert on a device/simulator set to a non-English language and
      confirm the title, message and Duplicate button are translated
- [ ] Re-read the catalog: keys are alphabetical, `extractionState` is
      `"manual"`, and no other block was touched

---

## Final verification (after all phases, by the parent)

#### Automated
- [x] `bash scripts/test.sh` prints `gate: ok` (iOS sim build → simulator
      pre-boot → `make test` → `make build-mac` → `make watch-build` → shell
      tests → `shellcheck`)

#### Manual
- [ ] `git log` shows one commit per phase; the tree is clean
