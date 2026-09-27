# Implementation Plan

## Overview

Add an additive, default-`true` `Checklist.showsOnWatch` flag (no
`currentVersion` bump), mutate it through `ChecklistStore.setShowsOnWatch`,
bind it to a store-backed "Show on watch" toggle in `ChecklistDetailView`, and
honour it by filtering the watch's already-derived collections so hidden
checklists (and all-hidden folders) disappear from the watch while iOS is
unchanged.

## Deviation from `structure.md` (Option A, agreed)

The watch-side filtering derivations move into **`CheckStitchCore`'s
`ChecklistGrouping`** (in `Checklist.swift`), with `WatchChecklistViewModel`
delegating to them. Reason: `WatchChecklistViewModel` lives in the
watchOS-only `CheckStitchWatch` target, which the macOS-hosted
`CheckStitchTests` bundle cannot import or link (its
`fileSystemSynchronizedGroups` is only `CheckStitchTests/` + the
`CheckStitchCore` package; there is no watch test leg in
`scripts/test.sh`). Putting the derivation in Core matches the existing
precedent — `WatchChecklistStore` lives in Core and is tested by
`WatchChecklistStoreTests`.

Consequences:
- The new filter tests live in `CheckStitchTests/ChecklistGroupingTests.swift`
  (Swift Testing, `@Test func`), not a new
  `CheckStitchTests/WatchChecklistViewModelTests.swift`.
- `WatchChecklistViewModel.looseChecklists`, `checklists(in:)` and the new
  `visibleFolders` become one-line delegations.
- The tests keep design decision #6's intent (one derivation serving both
  watch views, unit-testable without UI).

Two further small deviations, both required for correctness and noted inline:
`ChecklistMerge.mergedChecklists` copies winner fields one by one, so the new
field must join that copy; and `ChecklistStore.duplicate`/`freshCopy` carry
per-checklist booleans, so the new field must be carried there too. Test names
follow each file's existing style (XCTest files keep the `test` prefix;
Swift Testing files do not), unlike the shorter names written in
`structure.md`.

## Phase 1: Walking skeleton — toggle on iOS hides a loose checklist on the watch

Turning off "Show on watch" on the iOS edit-checklist screen persists the flag
through the synced envelope, and that checklist disappears from the watch main
list. One vertical slice: toggle → store → codec → envelope → watch store →
Core derivation → watch list.

### Changes

#### 1. Additive `showsOnWatch` field, codec, and Core loose-visibility helper
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add `showsOnWatch: Bool = true` to the memberwise init (after
`prefixesReminderNumbers`), the stored property, the `CodingKeys` case, the
decode, the encode, and the self-heal reconstruction; **do not touch
`currentVersion = 5`** and add no `migrated(at:)` case.

```swift
public init(
    id: UUID = UUID(), name: String = "New checklist", items: [ChecklistItem] = [],
    destinationListIdentifier: String? = nil,
    prefixesReminderNumbers: Bool = false,
    showsOnWatch: Bool = true,
    folderID: UUID? = nil,
    modifiedAt: Date = .distantPast, revision: Int = 0,
    itemOrder: [UUID]? = nil, orderRevision: Int = 0, orderModifiedAt: Date = .distantPast
) {
    // …
    self.prefixesReminderNumbers = prefixesReminderNumbers
    self.showsOnWatch = showsOnWatch
    // …
}
```

Stored property (after `prefixesReminderNumbers`):

```swift
/// Whether this checklist is offered on the Apple Watch. Default-on: it is
/// the first stored boolean that defaults to `true`, so an absent key reads
/// as "shown". Additive optional key: absent in v5-and-earlier payloads
/// decodes to `true` with no version bump (the `prefixesReminderNumbers`
/// precedent). Shares the checklist's coarse `revision`/`modifiedAt` clock,
/// so a toggle is decided by the same last-write-wins rule.
public var showsOnWatch: Bool
```

CodingKeys:

```swift
case id, name, items, destinationListIdentifier, prefixesReminderNumbers, showsOnWatch, folderID
```

Decode (after the `prefixesReminderNumbers` decode):

```swift
// Additive optional field: absent in v5-and-earlier payloads decodes to
// `true` (shown on the watch) with no version bump, matching the
// `prefixesReminderNumbers` precedent. This is the only default-`true`
// stored field, so the `?? true` is deliberate, not an oversight.
let showsOnWatch = try container.decodeIfPresent(Bool.self, forKey: .showsOnWatch) ?? true
```

Thread it into the self-heal reconstruction (this is load-bearing — omitting it
would silently rewrite a decoded `false` back to `true`):

```swift
self = Checklist(id: id, name: name, items: items,
                 destinationListIdentifier: destinationListIdentifier,
                 prefixesReminderNumbers: prefixesReminderNumbers,
                 showsOnWatch: showsOnWatch,
                 folderID: folderID,
                 modifiedAt: modifiedAt, revision: revision,
                 itemOrder: itemOrder, orderRevision: orderRevision, orderModifiedAt: orderModifiedAt)
    .normalizedOrder()
```

Encode (after the `prefixesReminderNumbers` encode; unconditional, matching the
"encoder writes every key" invariant):

```swift
try container.encode(showsOnWatch, forKey: .showsOnWatch)
```

Then extend `ChecklistGrouping` (same file, the enum at the end) with the
Phase 1 derivation:

```swift
/// The loose checklists the watch renders, in global order: loose (no folder,
/// or a `folderID` no longer known) and not hidden. The phone keeps sending
/// hidden checklists; the watch filters only at render time.
public static func visibleLooseChecklists(
    _ checklists: [Checklist], knownFolderIDs: Set<UUID>
) -> [Checklist] {
    checklists.filter { isLoose($0, knownFolderIDs: knownFolderIDs) && $0.showsOnWatch }
}
```

#### 2. Store mutation + carry the field through copy paths
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

Add `setShowsOnWatch`, directly after `setPrefixesReminderNumbers` (`:277-283`),
mirroring it one-for-one:

```swift
/// Sets a checklist's per-checklist "Show on watch" toggle and reports
/// whether it applied. Shares the checklist's coarse `revision`/`modifiedAt`
/// clock with `rename`/`setDestination`/`setPrefixesReminderNumbers`, so the
/// toggle rides the same last-write-wins rule. An unchanged value is a no-op,
/// so re-rendering the toggle never manufactures a spurious LWW win.
@discardableResult
func setShowsOnWatch(_ enabled: Bool, for id: UUID) -> SetDestinationOutcome {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return .notFound }
    guard checklists[index].showsOnWatch != enabled else { return .updated }
    checklists[index].showsOnWatch = enabled
    checklists[index].revision += 1
    checklists[index].modifiedAt = now()
    scheduleSave()
    return .updated
}
```

Carry the field in the two `Checklist(...)` reconstructions that copy
per-checklist booleans, so duplicating/importing does not silently reset it:
- `duplicate(id:name:)` (~`:181`): add `showsOnWatch: source.showsOnWatch,`
  after the `prefixesReminderNumbers:` line.
- `freshCopy(of:)` (~`:204`): add `showsOnWatch: checklist.showsOnWatch,`
  after the `prefixesReminderNumbers:` line.

#### 3. Winner-field copy in merge
**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: modify

`mergedChecklists` copies winner fields individually rather than replacing the
whole value, so the new field must join the copy inside the `if wins(...)`
block (~`:142`). Without this, a checklist whose newest edit is on another
device loses its hidden state on merge.

```swift
merged.prefixesReminderNumbers = remoteChecklist.prefixesReminderNumbers
merged.showsOnWatch = remoteChecklist.showsOnWatch
merged.folderID = remoteChecklist.folderID
```

(No new merge logic or clock — the field simply rides the existing
whole-checklist winner.)

#### 4. Toggle + binding in the edit screen
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Add a new `Section` directly after the Number Reminders section
(`:69-75`), and the binding next to `numberingBinding` (`:256-261`):

```swift
Section {
    Toggle(isOn: showOnWatchBinding(checklistID: checklistID)) {
        Label("Show on watch", systemImage: "applewatch")
    }
    .accessibilityIdentifier("checklistShowsOnWatchToggle")
} footer: {
    Text("Hidden checklists stay on your iPhone but are not shown on the Apple Watch.")
}
```

```swift
/// Per-selection write through the store for the "Show on watch" toggle. The
/// getter reads the store so a value that arrives over sync updates the
/// toggle; `.notFound` (deleted while this screen was open) is ignored,
/// matching `numberingBinding`.
private func showOnWatchBinding(checklistID: UUID) -> Binding<Bool> {
    Binding(
        get: { store.checklist(id: checklistID)?.showsOnWatch ?? true },
        set: { store.setShowsOnWatch($0, for: checklistID) }
    )
}
```

#### 5. Watch view model delegates the loose derivation
**File**: `CheckStitchWatch/WatchChecklistViewModel.swift`
**Action**: modify

```swift
/// Checklists with no folder (or a folder id the phone no longer knows), in
/// global order, excluding any the phone has hidden. Rendered as top-level
/// rows directly under the folder rows.
var looseChecklists: [Checklist] {
    let known = Set(store.folders.map(\.id))
    return ChecklistGrouping.visibleLooseChecklists(store.checklists, knownFolderIDs: known)
}
```

`checklists(in:)` and the views are unchanged in this phase (a hidden checklist
whose folder is known is only hidden by the Phase 2 folder work; Phase 1 proves
the loose path).

`WatchChecklistListView.swift` needs **no Phase 1 change** — it already renders
`viewModel.looseChecklists`.

#### 6. Localization — two new App keys
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add both entries to the `strings` map (Xcode keeps it key-sorted), each with
`extractionState: "manual"` and all six languages. `structure.md`'s file list
named only `"Show on watch"`, but it also mandates a behavior footer, so the
footer string is a second key.

```json
"Show on watch": {
  "extractionState": "manual",
  "localizations": {
    "de": { "stringUnit": { "state": "translated", "value": "Auf der Uhr anzeigen" } },
    "en": { "stringUnit": { "state": "translated", "value": "Show on watch" } },
    "es": { "stringUnit": { "state": "translated", "value": "Mostrar en el reloj" } },
    "fr": { "stringUnit": { "state": "translated", "value": "Afficher sur la montre" } },
    "ja": { "stringUnit": { "state": "translated", "value": "時計に表示" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "在手表上显示" } }
  }
}
```

```json
"Hidden checklists stay on your iPhone but are not shown on the Apple Watch.": {
  "extractionState": "manual",
  "localizations": {
    "de": { "stringUnit": { "state": "translated", "value": "Ausgeblendete Checklisten bleiben auf deinem iPhone, werden aber nicht auf der Apple Watch angezeigt." } },
    "en": { "stringUnit": { "state": "translated", "value": "Hidden checklists stay on your iPhone but are not shown on the Apple Watch." } },
    "es": { "stringUnit": { "state": "translated", "value": "Las listas ocultas permanecen en tu iPhone, pero no se muestran en el Apple Watch." } },
    "fr": { "stringUnit": { "state": "translated", "value": "Les listes masquées restent sur votre iPhone mais ne s'affichent pas sur l'Apple Watch." } },
    "ja": { "stringUnit": { "state": "translated", "value": "非表示のチェックリストはiPhoneに残りますが、Apple Watchには表示されません。" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "隐藏的清单会保留在 iPhone 上，但不会显示在 Apple Watch 上。" } }
  }
}
```

All non-English values differ from English, so no `excludedIdentities` entry is
needed.

#### 7. Localization fixture
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

In the `("App", [...])` list (`:12`):
- `"Show on watch",` — after `"Show a wallpaper behind the checklist.",`
- `"Hidden checklists stay on your iPhone but are not shown on the Apple Watch.",`
  — before `"How much the wallpaper fades for readability.",` (alphabetical, as
  the list intends).

#### 8. Tests
**File**: `CheckStitchTests/ChecklistCodecTests.swift` (XCTest)
**Action**: modify — add after `testPrefixesReminderNumbersSurvivesEnvelopeRoundTrip` (`:178`):

```swift
/// A v5 payload written without `showsOnWatch`: the absent key decodes to
/// `true` (the additive-optional guarantee for the first default-on field),
/// so older payloads keep showing every checklist without a version bump.
func testDecodesV5PayloadWithoutShowsOnWatchAsShown() throws {
    let id = UUID().uuidString
    let data = Data(#"{"version":5,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(id)","name":"Groceries","items":[]}]}"#.utf8)

    guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
        XCTFail("expected loaded, got \(ChecklistCodec.classify(data))")
        return
    }
    XCTAssertTrue(envelope.checklists.first?.showsOnWatch ?? false)
}

func testShowsOnWatchSurvivesEnvelopeRoundTrip() throws {
    let hidden = Checklist(name: "Hidden", items: [ChecklistItem(title: "Milk")], showsOnWatch: false)
    let shown = Checklist(name: "Shown")
    let envelope = ChecklistEnvelope(deviceID: "device-a", checklists: [hidden, shown])

    let data = try ChecklistCodec.encode(envelope)

    XCTAssertEqual(ChecklistCodec.classify(data), .loaded(envelope))
    XCTAssertEqual(ChecklistCodec.decode(data).map(\.showsOnWatch), [false, true])
}
```

**File**: `CheckStitchTests/ChecklistStoreTests.swift` (XCTest)
**Action**: modify — add a `setShowsOnWatch` suite after the
`setPrefixesReminderNumbers` suite (`:1882`), mirroring its three cases:

```swift
func testSetShowsOnWatchUpdatesRevisionAndPersists() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let clock = Clock()
    let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
    let created = store.create()
    clock.now = Date(timeIntervalSince1970: 5)

    XCTAssertEqual(store.setShowsOnWatch(false, for: created.id), .updated)

    let reloaded = makeStore(defaults: suite.defaults)
    XCTAssertEqual(reloaded.checklist(id: created.id)?.showsOnWatch, false)
    XCTAssertEqual(reloaded.checklist(id: created.id)?.revision, 2)
    XCTAssertEqual(reloaded.checklist(id: created.id)?.modifiedAt, clock.now)
}

func testSetShowsOnWatchUnchangedValueIsNoOp() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let clock = Clock()
    let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
    let created = store.create()
    store.setShowsOnWatch(false, for: created.id)
    let revisionAfterToggle = store.checklist(id: created.id)?.revision
    let modifiedAfterToggle = store.checklist(id: created.id)?.modifiedAt
    clock.now = Date(timeIntervalSince1970: 9)

    XCTAssertEqual(store.setShowsOnWatch(false, for: created.id), .updated)

    XCTAssertEqual(store.checklist(id: created.id)?.revision, revisionAfterToggle)
    XCTAssertEqual(store.checklist(id: created.id)?.modifiedAt, modifiedAfterToggle)
}

func testSetShowsOnWatchForUnknownChecklistReturnsNotFound() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let store = makeStore(defaults: suite.defaults)

    XCTAssertEqual(store.setShowsOnWatch(false, for: UUID()), .notFound)
    XCTAssertTrue(store.checklists.isEmpty)
}
```

**File**: `CheckStitchTests/ChecklistGroupingTests.swift` (Swift Testing)
**Action**: modify — append:

```swift
@Test
func visibleLooseChecklistsExcludeHiddenChecklists() {
    let shown = Checklist(name: "Shown")
    let hidden = Checklist(name: "Hidden", showsOnWatch: false)

    let visible = ChecklistGrouping.visibleLooseChecklists([shown, hidden], knownFolderIDs: [])

    #expect(visible == [shown])
}
```

**File**: `CheckStitchTests/ChecklistDetailViewTests.swift` (Swift Testing)
**Action**: modify — append (the view's private binding cannot be read from a
headless test, so the default/persistence live at the model+store layer and the
view gets a render canary, following `detailViewRendersItemsWithDescriptions`):

```swift
/// The flag is default-on: a freshly created checklist is shown on the watch.
@Test
func showOnWatchDefaultsOn() {
    #expect(Checklist(name: "Groceries").showsOnWatch)
}

/// Toggling off persists through the store the toggle binds to.
@Test
func togglingShowOnWatchPersistsThroughTheStore() {
    let defaults = makeIsolatedDefaults()
    let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
    let checklist = store.create(name: "Groceries")

    store.setShowsOnWatch(false, for: checklist.id)

    #expect(store.checklist(id: checklist.id)?.showsOnWatch == false)
}

/// The new section renders on the detail screen: staging the view against a
/// store whose checklist is hidden must not crash.
@Test
func detailViewRendersWithAHiddenChecklist() {
    let defaults = makeIsolatedDefaults()
    let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
    let checklist = store.create(name: "Groceries")
    store.setShowsOnWatch(false, for: checklist.id)

    let view = ChecklistDetailView(checklistID: checklist.id).environment(store)
    #if os(macOS)
    #expect(ImageRenderer(content: view).nsImage != nil)
    #else
    #expect(ImageRenderer(content: view).uiImage != nil)
    #endif
}
```

### Verification
#### Automated
- [x] `make test-unit` — the codec (absent-key + round trip), store (3 cases),
      grouping, and detail-view additions pass with no regressions.
- [x] `make watch-build` — the watch target compiles with the delegating
      `looseChecklists`.
- [x] `scripts/l10n-check.sh` — prints `l10n-check: ok`, including both new keys
      in all six languages.
- [x] Confirm no `currentVersion` change: `rg -n 'currentVersion(:|=)' CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` still shows `5`.

#### Manual
- [ ] `make run`, open a checklist's detail screen: "Show on watch" appears in
      its own section, default **on**, with the footer text.
- [ ] Toggle it off, leave and re-enter the screen: it stays off (store-backed).
- [ ] Toggle back on: it flips back.

---

## Phase 2: Folder semantics — folder detail and folder rows honour hiding

A folder's detail list shows only shown checklists, and a folder row disappears
from the watch main list when it has ≥1 member and every member is hidden. A
folder with zero members still appears.

### Changes

#### 1. Core folder derivations
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify — add to `ChecklistGrouping`:

```swift
/// A folder's visible checklists, in global order: filed under `folder` and
/// not hidden.
public static func visibleChecklists(
    in folder: Folder, from checklists: [Checklist]
) -> [Checklist] {
    checklists.filter { $0.folderID == folder.id && $0.showsOnWatch }
}

/// The folders the watch renders: a folder stays when it has no members, or at
/// least one visible member; it drops only when it has members and all of them
/// are hidden. Membership stays derived from `folderID` — no folder-side child
/// list is introduced.
public static func visibleFolders(
    _ folders: [Folder], checklists: [Checklist]
) -> [Folder] {
    folders.filter { folder in
        let members = checklists.filter { $0.folderID == folder.id }
        return members.isEmpty || members.contains { $0.showsOnWatch }
    }
}
```

#### 2. Watch view model delegates the folder derivations
**File**: `CheckStitchWatch/WatchChecklistViewModel.swift`
**Action**: modify

```swift
/// Folders with at least one visible checklist, plus empty folders. A folder
/// whose members are all hidden drops off the root list.
var visibleFolders: [Folder] {
    ChecklistGrouping.visibleFolders(store.folders, checklists: store.checklists)
}

/// The checklists inside `folder`, in global order, excluding hidden ones.
func checklists(in folder: Folder) -> [Checklist] {
    ChecklistGrouping.visibleChecklists(in: folder, from: store.checklists)
}
```

#### 3. Watch root list renders visible folders
**File**: `CheckStitchWatch/WatchChecklistListView.swift`
**Action**: modify

```swift
ForEach(viewModel.visibleFolders) { folder in
    NavigationLink {
        WatchFolderDetailView(folder: folder)
    } label: {
        Label(folder.name, systemImage: "folder")
    }
}
```

No inline filtering — the collection is already filtered. No change to the
`viewModel.checklists.isEmpty` empty-state branch or to
`WatchFolderDetailView` (it keeps rendering `viewModel.checklists(in: current)`,
which now filters).

#### 4. Tests
**File**: `CheckStitchTests/ChecklistGroupingTests.swift` (Swift Testing)
**Action**: modify — append:

```swift
@Test
func visibleChecklistsInFolderExcludeHiddenChecklists() {
    let folder = Folder(name: "Errands")
    let shown = Checklist(name: "Shown", folderID: folder.id)
    let hidden = Checklist(name: "Hidden", folderID: folder.id, showsOnWatch: false)

    let visible = ChecklistGrouping.visibleChecklists(in: folder, from: [hidden, shown])

    #expect(visible == [shown])
}

@Test
func folderWithSomeVisibleMembersStaysVisible() {
    let folder = Folder(name: "Errands")
    let shown = Checklist(name: "Shown", folderID: folder.id)
    let hidden = Checklist(name: "Hidden", folderID: folder.id, showsOnWatch: false)

    let visible = ChecklistGrouping.visibleFolders([folder], checklists: [hidden, shown])

    #expect(visible == [folder])
}

@Test
func folderWithEveryMemberHiddenIsHidden() {
    let folder = Folder(name: "Errands")
    let hidden = Checklist(name: "Hidden", folderID: folder.id, showsOnWatch: false)

    let visible = ChecklistGrouping.visibleFolders([folder], checklists: [hidden])

    #expect(visible.isEmpty)
}

@Test
func emptyFolderStaysVisible() {
    let folder = Folder(name: "Empty")

    let visible = ChecklistGrouping.visibleFolders([folder], checklists: [])

    #expect(visible == [folder])
}
```

### Verification
#### Automated
- [x] `make test-unit` — the four folder-derivation cases pass and the
      Phase 1 grouping cases still pass.
- [x] `make watch-build` — the watch target compiles with `visibleFolders`.
- [x] `make build` — the iOS target compiles (no accidental app-target use of the
      new `ChecklistGrouping` helpers).

#### Manual
- [ ] `make run` and open a folder on the phone: its iOS list is unchanged
      (hidden members stay visible on iOS).
- [ ] (Watch check lands in Phase 3's live pass.)

---

## Phase 3: Hardening — sync conflicts, edge cases, and on-watch verification

Pins the behaviours later changes must not break: merge winner-wins for the
flag, older-client tolerance of the new key, unknown/tombstoned folders, and
the on-device watch outcome.

### Changes

#### 1. Merge conflict tests
**File**: `CheckStitchTests/ChecklistMergeTests.swift` (Swift Testing)
**Action**: modify — append, mirroring `winnerNumberingOverwritesLoser` /
`loserNumberingIsPreservedWhenNonWinning` (`:755-780`):

```swift
@Test
func winnerShowOnWatchOverwritesLoser() {
    let id = UUID()
    var newer = checklist(id: id, name: "newer", revision: 2, modifiedAt: Date(timeIntervalSince1970: 2))
    newer.showsOnWatch = false
    let older = checklist(id: id, name: "older", revision: 1, modifiedAt: Date(timeIntervalSince1970: 1))

    let merged = ChecklistMerge.merge(
        local: envelope(device: "device-a", checklists: [older]),
        remote: envelope(device: "device-b", checklists: [newer])
    )

    #expect(merged.checklists.first?.showsOnWatch == false, "the newest editor controls the show-on-watch toggle")
}

@Test
func loserShowOnWatchIsPreservedWhenNonWinning() {
    let id = UUID()
    var newer = checklist(id: id, name: "newer", revision: 2, modifiedAt: Date(timeIntervalSince1970: 2))
    newer.showsOnWatch = false
    let older = checklist(id: id, name: "older", revision: 1, modifiedAt: Date(timeIntervalSince1970: 1))

    let merged = ChecklistMerge.merge(
        local: envelope(device: "device-a", checklists: [newer]),
        remote: envelope(device: "device-b", checklists: [older])
    )

    #expect(merged.checklists.first?.showsOnWatch == false, "an older revision must not leak its show-on-watch value in")
}
```

#### 2. Older-client / unknown-key tolerance
**File**: `CheckStitchTests/ChecklistCodecTests.swift` (XCTest)
**Action**: modify — append:

```swift
/// A v5 payload that carries the new key plus a key this build does not know
/// still classifies `.loaded`: additive fields must never turn a readable
/// envelope into `.unreadable`.
func testPayloadWithUnrecognizedKeyStillClassifiesLoaded() throws {
    let id = UUID().uuidString
    let data = Data(#"{"version":5,"deviceID":"device-a","tombstones":[],"futureField":"x","checklists":[{"id":"\#(id)","name":"Groceries","items":[],"showsOnWatch":false,"futureKey":7}]}"#.utf8)

    guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
        XCTFail("expected loaded, got \(ChecklistCodec.classify(data))")
        return
    }
    XCTAssertEqual(envelope.checklists.first?.showsOnWatch, false)
}
```

#### 3. Unknown / tombstoned folder edge cases
**File**: `CheckStitchTests/ChecklistGroupingTests.swift` (Swift Testing)
**Action**: modify — append. Both paths resolve through the same `isLoose`
rule (a tombstoned folder arrives as an unknown id), and the tests pin that a
hidden checklist never resurfaces in the loose list while a shown sibling does.

```swift
@Test
func hiddenChecklistWithUnknownFolderIsNotShownAsLoose() {
    let hidden = Checklist(name: "Hidden", folderID: UUID(), showsOnWatch: false)
    let visible = Checklist(name: "Visible", folderID: UUID())

    let loose = ChecklistGrouping.visibleLooseChecklists([hidden, visible], knownFolderIDs: [])

    #expect(loose == [visible])
}

@Test
func hiddenChecklistWithTombstonedFolderIsNotShown() {
    let tombstoned = UUID()
    let hidden = Checklist(name: "Hidden", folderID: tombstoned, showsOnWatch: false)
    let shown = Checklist(name: "Shown", folderID: tombstoned)

    let loose = ChecklistGrouping.visibleLooseChecklists([hidden, shown], knownFolderIDs: [])

    #expect(loose == [shown])
    #expect(!loose.contains(hidden))
}
```

### Verification
#### Automated
- [x] `make test-unit` — merge, codec and grouping additions pass.
- [ ] `bash scripts/test.sh` — full gate prints `gate: ok` (includes
      `make build`, `make test`, `make build-mac`, `make watch-build`,
      `scripts/tests/run.sh`, shellcheck; warnings-as-errors enforced).
- [x] `git grep -n 'currentVersion' CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` shows the value unchanged at `5`.

#### Manual (required — static evidence cannot close this ticket)
- [ ] `bash scripts/run-watch.sh` builds, installs and launches
      `CheckStitchWatch` on the paired Apple Watch.
- [ ] With the watch app open, toggle "Show on watch" **off** for a loose
      checklist on the phone: the row disappears from the watch's main list.
- [ ] Toggle it back **on**: the row returns.
- [ ] Put two hidden checklists in one folder: the folder row disappears from
      the watch root, and re-enabling one member brings the folder back.
- [ ] Leave an empty folder: its row stays on the watch root.
- [ ] State what the user should see in the completion artifact (per
      `AGENTS.md`, sync/hide tickets cannot close on unit tests alone).

---

## File inventory

| File | Phase | Action |
| --- | --- | --- |
| `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` | 1, 2 | modify (`showsOnWatch` + codec + `ChecklistGrouping` helpers) |
| `CheckStitch/ChecklistStore.swift` | 1 | modify (`setShowsOnWatch`, carry in `duplicate`/`freshCopy`) |
| `CheckStitch/ChecklistMerge.swift` | 1 | modify (winner-field copy) |
| `CheckStitch/ChecklistDetailView.swift` | 1 | modify (toggle + binding) |
| `CheckStitch/Localizable.xcstrings` | 1 | modify (2 App keys) |
| `CheckStitchTests/LocalizationFixtures.swift` | 1 | modify (2 `requiredKeys` entries) |
| `CheckStitchWatch/WatchChecklistViewModel.swift` | 1, 2 | modify (delegations) |
| `CheckStitchWatch/WatchChecklistListView.swift` | 2 | modify (`visibleFolders`) |
| `CheckStitchWatch/WatchFolderDetailView.swift` | — | unchanged (renders filtered `members`) |
| `CheckStitchTests/ChecklistCodecTests.swift` | 1, 3 | modify (3 tests) |
| `CheckStitchTests/ChecklistStoreTests.swift` | 1 | modify (3 tests) |
| `CheckStitchTests/ChecklistGroupingTests.swift` | 1, 2, 3 | modify (7 tests) |
| `CheckStitchTests/ChecklistDetailViewTests.swift` | 1 | modify (3 tests) |
| `CheckStitchTests/ChecklistMergeTests.swift` | 3 | modify (2 tests) |

No new files, no PBX project edits (`PBXFileSystemSynchronizedRootGroup` picks
up edits to existing files), no schema/version migration.
