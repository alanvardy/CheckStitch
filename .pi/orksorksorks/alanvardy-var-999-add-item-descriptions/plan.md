# Implementation Plan

## Overview

Add a non-optional `description: String` (default `""`) to `ChecklistItem` that
rides the existing whole-item LWW merge with **no version bump**, is editable in
the iOS detail editor, shown as a caption on the watch, and forwarded to
`EKReminder.notes` on run. Every stage ships its tests and must be green before
the next.

**Branch state note:** this worktree is 28 commits behind `origin/main`; the
tree currently has `currentVersion == 2`. All snippets below are written against
the **post-rebase** tree (`currentVersion == 3`, VAR-991 destination seam,
VAR-995 `itemOrder`). Stage 0 performs that rebase first.

**Deviations from `structure.md` (documented, resolved):**
- `ChecklistStoreTests` and `ChecklistCodecTests` are **XCTest** suites (not
  Swift Testing), so the Stage 1/2 test methods use the `test…` prefix and
  `XCTAssert*`; `structure.md` listed behaviour-named functions. Same coverage,
  adapted to the file's existing style.
- Stage 5 cannot pin the `descriptionBinding` getter/setter directly: the
  binding is a `private` method on the view and reads the `@Environment` store,
  which traps in the headless test host (the existing `ChecklistDetailViewTests`
  comment documents this) — only `String(describing:)` value slots and
  `ImageRenderer` body staging are reachable, neither of which exposes a private
  closure. The store round trip is pinned in Stage 2; Stage 5 adds an
  `ImageRenderer` render canary (pattern from `ViewRenderTests`) plus manual
  on-device verification. No re-run of structure/design is required — the
  behaviour under test (the store mutator) is fully covered.

---

## Phase 0: Rebase on `origin/main` (prerequisite)

### Changes

#### 1. Clean the working tree and rebase
**Action**: git operation only, no file edits.

The only branch-unique commit is `b37addd chore: start …` (adds `DELETEME`);
the worktree has an unstaged deletion of `DELETEME`. Restore it so the rebase
does not have to carry a dirty tree, then rebase.

```bash
git fetch origin
git restore DELETEME          # discard the unstaged deletion of the scratch marker
git rebase origin/main         # replay b37addd on top of e3ddbac (v3 + destination seam)
```

Conflicts are not expected: `ChecklistItem` is untouched by VAR-991/995 and
`b37addd` only adds a 1-line file. If `DELETEME` conflicts, keep the branch's
copy (`git checkout --ours DELETEME && git add DELETEME`) and continue with
`git -c core.editor=true rebase --continue`.

### Verification
#### Automated
- [x] `git rev-list --count HEAD..origin/main` prints `0`
- [x] `grep -n "currentVersion = 3" CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` matches
- [x] `make test-unit` passes on the rebased tree (pre-change baseline)

#### Manual
- [ ] `git log --oneline -1` shows `b37addd` on top of `origin/main`

---

## Phase 1: Model & codec — the schema layer

### Changes

#### 1. `ChecklistItem` field, init param, helper, codec
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add the stored property, a defaulted init parameter (label added, so every
existing call site still compiles), a computed helper, and the codec key. Do
**not** change `ChecklistCodec.currentVersion` or `migrated(at:)`.

```swift
public init(id: UUID = UUID(), title: String, description: String = "", modifiedAt: Date = .distantPast, revision: Int = 0) {
    self.id = id
    self.title = title
    self.description = description
    self.modifiedAt = modifiedAt
    self.revision = revision
}

public let id: UUID
public var title: String
public var description: String
public var modifiedAt: Date
public var revision: Int

/// True when the item carries any description text. Whitespace is preserved
/// verbatim (matching `title`); only the empty string means "no description".
/// Consumed by the watch row and the reminder-notes normalisation.
public var hasDescription: Bool { !description.isEmpty }

private enum CodingKeys: String, CodingKey { case id, title, description, modifiedAt, revision }

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    // Additive optional field: absent key decodes to "", matching the
    // destinationListIdentifier precedent — no version bump.
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
}

public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(description, forKey: .description)
    try container.encode(modifiedAt, forKey: .modifiedAt)
    try container.encode(revision, forKey: .revision)
}
```

#### 2. Item codec tests
**File**: `CheckStitchTests/ChecklistItemTests.swift`
**Action**: modify

`isBlank` stays title-derived; add the description pins. (Swift Testing suite,
behaviour-named functions.)

```swift
@Test
func descriptionDefaultsToEmptyWhenKeyIsAbsent() throws {
    let id = UUID().uuidString
    let json = Data(#"{"id":"\#(id)","title":"Milk"}"#.utf8)
    let decoded = try JSONDecoder().decode(ChecklistItem.self, from: json)
    #expect(decoded.description == "")
    #expect(!decoded.hasDescription)
}

@Test
func descriptionRoundTripsThroughCodable() throws {
    let item = ChecklistItem(title: "Milk", description: "2 litres, semi-skimmed")
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(ChecklistItem.self, from: data)
    #expect(decoded == item)
    #expect(decoded.description == "2 litres, semi-skimmed")
    #expect(decoded.hasDescription)
}

@Test(arguments: ["", " ", "\n"])
func descriptionDoesNotUnblankAnEmptyTitle(_ description: String) {
    #expect(ChecklistItem(title: "  ", description: description).isBlank)
}
```

#### 3. Envelope codec tests
**File**: `CheckStitchTests/ChecklistCodecTests.swift`
**Action**: modify

XCTest suite — `test`-prefixed methods.

```swift
/// A v3 envelope whose item carries no `description` key: must stay `.loaded`
/// with an empty description (the additive-field guarantee).
func testV3ItemWithoutDescriptionClassifiesLoadedAsEmpty() throws {
    let itemID = UUID().uuidString
    let data = Data(#"{"version":3,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(itemID)","title":"Milk"}]}]}"#.utf8)

    guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
        XCTFail("expected loaded, got \(ChecklistCodec.classify(data))")
        return
    }
    XCTAssertEqual(envelope.checklists.first?.items.first?.description, "")
}

func testDescriptionSurvivesEnvelopeRoundTrip() throws {
    let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", description: "2 litres")])
    let data = try ChecklistCodec.encode(ChecklistEnvelope(deviceID: "device-a", checklists: [checklist]))

    guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
        XCTFail("expected loaded, got \(ChecklistCodec.classify(data))")
        return
    }
    XCTAssertEqual(envelope.checklists.first?.items.first?.description, "2 litres")
    XCTAssertTrue(String(data: data, encoding: .utf8)?.contains(#""description""#) ?? false)
}

/// Sad path: a malformed (non-string) description throws, so the whole payload
/// is `.unreadable` — only whole-key absence is tolerant.
func testMalformedDescriptionMakesPayloadUnreadable() {
    let data = Data(#"{"version":3,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"x","items":[{"id":"\#(UUID().uuidString)","title":"Milk","description":42}]}]}"#.utf8)
    XCTAssertEqual(ChecklistCodec.classify(data), .unreadable)
}
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make test-unit` specifically exercises the three new `ChecklistCodecTests` methods and the `ChecklistItemTests` description tests

#### Manual
- [ ] Inspect encoded JSON for one item and confirm a `"description"` key is present and `currentVersion` file line is still `3`

---

## Phase 2: Store — description mutation & duplication

### Changes

#### 1. `updateItemDescription` mutator + duplicate copy
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

Add the sibling mutator directly after `updateItem(...)`; leave `updateItem`
and `addItem` untouched. Carry the description through `duplicate`.

```swift
/// Edits only the item's description, stamping the item's sync identity and
/// debouncing like `updateItem`. Item ops never touch the checklist's own
/// `revision`/`modifiedAt` (see `Checklist` doc).
func updateItemDescription(checklistID: UUID, itemID: UUID, description: String) {
    guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
          let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
    else { return }
    checklists[checklistIndex].items[itemIndex].description = description
    checklists[checklistIndex].items[itemIndex].revision += 1
    checklists[checklistIndex].items[itemIndex].modifiedAt = now()
    scheduleSave()
}
```

In `duplicate(id:name:)`, change the item mapping to:

```swift
items: source.items.map { ChecklistItem(title: $0.title, description: $0.description, modifiedAt: now(), revision: 1) },
```

#### 2. Store tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

XCTest suite — `test`-prefixed, `XCTAssert*`. Reuse `makeDefaults()` / `makeStore` /
the `Clock` fixture already in the file. Place near `testMutationsStampRevisionAndTimestamp`.

```swift
func testDescriptionEditBumpsItemRevisionNotChecklist() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let clock = Clock()
    let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
    let created = store.create()
    store.addItem(to: created.id)
    let item = store.checklist(id: created.id)?.items.first

    clock.now = Date(timeIntervalSince1970: 1_000)
    store.updateItemDescription(checklistID: created.id, itemID: item?.id ?? UUID(), description: "2 litres")

    XCTAssertEqual(store.checklist(id: created.id)?.items.first?.description, "2 litres")
    XCTAssertEqual(store.checklist(id: created.id)?.items.first?.revision, 2)     // 1 on add, +1
    XCTAssertEqual(store.checklist(id: created.id)?.items.first?.modifiedAt, clock.now)
    XCTAssertEqual(store.checklist(id: created.id)?.revision, 1)                 // checklist untouched
    XCTAssertEqual(store.checklist(id: created.id)?.modifiedAt, created.modifiedAt)
}

func testDescriptionEditPersistsAndReloads() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let store = makeStore(defaults: suite.defaults)
    let created = store.create()
    store.addItem(to: created.id)
    let item = store.checklist(id: created.id)?.items.first
    store.updateItemDescription(checklistID: created.id, itemID: item?.id ?? UUID(), description: "2 litres")

    let reloaded = makeStore(defaults: suite.defaults)
    XCTAssertEqual(reloaded.checklist(id: created.id)?.items.first?.description, "2 litres")
}

func testTitleEditLeavesDescriptionIntact() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let store = makeStore(defaults: suite.defaults)
    let created = store.create()
    store.addItem(to: created.id)
    let id = store.checklist(id: created.id)?.items.first?.id ?? UUID()
    store.updateItemDescription(checklistID: created.id, itemID: id, description: "2 litres")
    store.updateItem(checklistID: created.id, itemID: id, title: "Milk")

    XCTAssertEqual(store.checklist(id: created.id)?.items.first?.title, "Milk")
    XCTAssertEqual(store.checklist(id: created.id)?.items.first?.description, "2 litres")
}

func testDuplicateCopiesDescription() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let store = makeStore(defaults: suite.defaults)
    let source = store.create(name: "Groceries")
    store.addItem(to: source.id)
    let item = store.checklist(id: source.id)?.items.first
    store.updateItemDescription(checklistID: source.id, itemID: item?.id ?? UUID(), description: "2 litres")

    let copy = store.duplicate(id: source.id, name: "Groceries copy")

    XCTAssertEqual(copy?.items.first?.description, "2 litres")
    XCTAssertEqual(copy?.items.first?.revision, 1)          // fresh copy, not source's 2
    XCTAssertNotEqual(copy?.items.first?.id, item?.id)
}

/// Sad path: unknown ids are silent no-ops, exactly like `updateItem`.
func testDescriptionEditUnknownIDsIsNoOp() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
    let store = makeStore(defaults: suite.defaults)
    let created = store.create()
    store.addItem(to: created.id)

    store.updateItemDescription(checklistID: created.id, itemID: UUID(), description: "ghost")
    store.updateItemDescription(checklistID: UUID(), itemID: UUID(), description: "ghost")

    XCTAssertEqual(store.checklist(id: created.id)?.items.first?.description, "")
}
```

#### 3. `makeItem` fixture gains an optional description
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

```swift
func makeItem(_ title: String, description: String = "") -> ChecklistItem {
    ChecklistItem(title: title, description: description)
}
```

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] Description edit/reload, duplicate-copy, and no-op cases are exercised

#### Manual
- [ ] `grep -n "updateItemDescription" CheckStitch/ChecklistStore.swift` shows the new mutator and no change to `updateItem`/`addItem`

---

## Phase 3: Sync & merge hardening — tests only

No production files change. Whole-item LWW (`ChecklistMerge.swift:110`) already
carries the new field through the winner struct; these tests pin that.

### Changes

#### 1. Merge tests
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

Extend the local `item(...)` helper with `description: String = ""`, then add
(Swift Testing, behaviour-named):

```swift
@Test
func descriptionFollowsTheWholeItemLWinner() {
    let id = UUID()
    let localItem = item(id: id, title: "Milk", description: "local note", revision: 2,
                         modifiedAt: Date(timeIntervalSince1970: 2_000))
    let remoteItem = item(id: id, title: "Milk", description: "remote note", revision: 3,
                          modifiedAt: Date(timeIntervalSince1970: 3_000))
    let merged = ChecklistMerge.merge(
        local: envelope(device: "device-a", checklists: [checklist(id: id, name: "Groceries", revision: 1, items: [localItem])]),
        remote: envelope(device: "device-b", checklists: [checklist(id: id, name: "Groceries", revision: 1, items: [remoteItem])]))
    #expect(merged.checklists.first?.items.first?.description == "remote note")
}

@Test
func distinctItemDescriptionsBothSurvive() {
    let checklistID = UUID()
    let a = item(id: UUID(), title: "Milk", description: "a note", revision: 1)
    let b = item(id: UUID(), title: "Eggs", description: "b note", revision: 1)
    let merged = ChecklistMerge.merge(
        local: envelope(device: "device-a", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [a])]),
        remote: envelope(device: "device-b", checklists: [checklist(id: checklistID, name: "Groceries", revision: 1, items: [b])]))
    #expect(Set(merged.checklists.first?.items.map(\.description) ?? []) == ["a note", "b note"])
}
```

(`checklist(id:name:revision:items:)` and `item(...)` are the file's existing
local helpers at the bottom of the file.)

#### 2. Sync service round-trip test
**File**: `CheckStitchTests/ChecklistSyncServiceTests.swift`
**Action**: modify

XCTest suite. Add one test using the existing `remoteChecklist`/`envelopeData`
helpers and `makeService`:

```swift
func testDescriptionSurvivesMergeAndPush() async throws {
    let suite = makeDefaults()
    let store = makeStore(defaults: suite.defaults)
    let sync = InMemoryChecklistSync()
    let service = makeService(sync: sync, store: store)
    let item = ChecklistItem(title: "Milk", description: "2 litres")
    let remote = Checklist(name: "Groceries", items: [item])
    sync.stored = try ChecklistCodec.encode(ChecklistEnvelope(deviceID: "device-b", checklists: [remote]))

    await service.refresh()

    XCTAssertEqual(store.checklists.first?.items.first?.description, "2 litres")
    let pushed = try XCTUnwrap(sync.stored)
    XCTAssertEqual(ChecklistCodec.decode(pushed).first?.items.first?.description, "2 litres")
}
```

(Adjust to the exact `refresh`/`reconcile` entry-point name used by the file —
`ChecklistSyncService` is exercised via `service.refresh()` in
`localEmptyAppliesRemote`.)

#### 3. Watch context round-trip test
**File**: `CheckStitchTests/WatchChecklistStoreTests.swift`
**Action**: modify

Swift Testing. Mirror `contextReplacesTheChecklistList` and
`malformedContextLeavesThePreviousListIntact` / `destinationFieldSurvivesTheWatchTransport`:

```swift
@Test
func descriptionSurvivesTheWatchTransport() throws {
    let transport = FakeChecklistSyncTransport()
    let store = WatchChecklistStore(transport: transport)
    let expected = [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", description: "2 litres")])]
    let data = try ChecklistCodec.encode(ChecklistEnvelope(deviceID: "device-a", checklists: expected))

    transport.onMessage?(.context(data))

    #expect(store.checklists.first?.items.first?.description == "2 litres")
}
```

#### 4. No production change
**Action**: none.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] Description bytes survive an `encode` → `classify` → `decode` round trip in both the merge and watch-context tests

#### Manual
- [ ] `git diff --name-only` for this stage lists only `CheckStitchTests/` files

---

## Phase 4: Reminder destination seam — description → `EKReminder.notes`

### Changes

#### 1. Protocol signature
**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`
**Action**: modify

```swift
@MainActor
public protocol ReminderDestinationTargeting {
    func requestAccess() async throws -> Bool
    func reminderLists() async throws -> ReminderListsSnapshot
    func create(title: String, notes: String?, in list: ReminderListOption) async throws
}
```

#### 2. EventKit adapter
**File**: `CheckStitch/EventKitReminderDestination.swift`
**Action**: modify

```swift
func create(title: String, notes: String?, in list: ReminderListOption) async throws {
    guard let calendar = eventStore.calendars(for: .reminder)
        .first(where: { $0.calendarIdentifier == list.id })
    else { throw ReminderDestinationError.listMissing }

    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    if let notes { reminder.notes = notes }   // nil leaves notes unset
    reminder.calendar = calendar
    #if !os(watchOS)
        try eventStore.save(reminder, commit: true)
    #endif
}
```

#### 3. Run path normalisation
**File**: `CheckStitch/ChecklistReminders.swift`
**Action**: modify

The single nil-normalisation point (design decision 4: stored verbatim, only
emptiness maps to `nil`):

```swift
for item in checklist.items where !item.isBlank {
    try await targeting.create(
        title: item.title,
        notes: item.description.isEmpty ? nil : item.description,
        in: destination)
    created += 1
}
```

#### 4. Spy records notes
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

```swift
final class SpyReminderDestination: ReminderDestinationTargeting {
    var accessGranted = true
    var accessError: Error?
    var lists = ReminderListsSnapshot(options: [], defaultIdentifier: nil)
    var createError: Error?
    private(set) var createdTitles: [String] = []
    private(set) var createdNotes: [String?] = []
    private(set) var createdListIDs: [String] = []

    func requestAccess() async throws -> Bool {
        if let accessError { throw accessError }
        return accessGranted
    }

    func reminderLists() async throws -> ReminderListsSnapshot { lists }

    func create(title: String, notes: String?, in list: ReminderListOption) async throws {
        if let createError { throw createError }
        createdTitles.append(title)
        createdNotes.append(notes)
        createdListIDs.append(list.id)
    }
}
```

#### 5. Reminder-seam tests
**File**: `CheckStitchTests/ChecklistRemindersTests.swift`
**Action**: modify

Swift Testing, `@MainActor` suite already. Add:

```swift
@Test
func notesForwardDescription() async {
    let spy = SpyReminderDestination()
    spy.lists = snapshot()
    let checklist = Checklist(
        items: [makeItem("Milk", description: "2 litres"), makeItem("Eggs", description: "a dozen")],
        destinationListIdentifier: "list-a")

    let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

    #expect(outcome == .created(count: 2))
    #expect(spy.createdNotes == ["2 litres", "a dozen"])
}

@Test
func blankDescriptionSendsNilNotes() async {
    let spy = SpyReminderDestination()
    spy.lists = snapshot()
    let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

    _ = await ChecklistReminders.create(from: checklist, targeting: spy)

    #expect(spy.createdNotes == [nil])
}

/// Sad path: the existing denial/missing-destination guards still create
/// nothing, so no notes can leak.
@Test
func deniedAccessNeverSendsNotes() async {
    let spy = SpyReminderDestination()
    spy.accessGranted = false
    spy.lists = snapshot()
    let checklist = Checklist(items: [makeItem("Milk", description: "2 litres")], destinationListIdentifier: "list-a")

    let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

    #expect(outcome == .permissionDenied)
    #expect(spy.createdNotes.isEmpty)
}
```

**Deliberately unchanged**: the legacy core `ChecklistCreator` /
`ReminderCreating` seam (`CheckStitchCore/.../ChecklistCreator.swift`,
`ReminderCreating.swift`) — test-only, off the production path.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make build-mac` passes (protocol conformance compiles on macOS)
- [x] `grep -rn "func create(title:" CheckStitch CheckStitchCore CheckStitchTests` shows only the two conformances with the new signature

#### Manual
- [ ] `grep -n "ChecklistCreator" CheckStitch/ContentView.swift CheckStitch/MyApp.swift` shows no production call site (unchanged)

---

## Phase 5: iOS editor — per-row description field

### Changes

#### 1. Detail view: binding + field
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Add the sibling of `titleBinding` (per-keystroke write, same shape) and a
vertical `TextField` under the title inside the existing `Section("Items")`.

```swift
Section("Items") {
    ForEach(checklist.items) { item in
        VStack(alignment: .leading, spacing: 4) {
            TextField("Item", text: titleBinding(checklistID: checklistID, itemID: item.id))
            TextField("Description", text: descriptionBinding(checklistID: checklistID, itemID: item.id), axis: .vertical)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("itemDescriptionField")
        }
    }
    .onDelete { offsets in
        store.removeItems(from: checklistID, at: offsets)
    }
    .onMove { offsets, destination in
        store.moveItems(checklistID: checklistID, from: offsets, to: destination)
    }
}
```

```swift
/// Per-keystroke description write, mirroring `titleBinding`. The getter
/// re-finds the item by id each read; a missing checklist/item reads as "".
private func descriptionBinding(checklistID: UUID, itemID: UUID) -> Binding<String> {
    Binding(
        get: {
            store.checklist(id: checklistID)?.items.first { $0.id == itemID }?.description ?? ""
        },
        set: { store.updateItemDescription(checklistID: checklistID, itemID: itemID, description: $0) }
    )
}
```

#### 2. Localization — "Description" key
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Add a `"Description"` entry (alphabetically near `"Dark"`/`"Done"`) with all six
languages; `catalogsHaveAllSixLanguages` requires every catalog entry to carry
all six. Suggested values: en `Description`, de `Beschreibung`,
es `Descripción`, fr `Description`, ja `説明`, zh-Hans `描述`.

```jsonc
"Description" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Description" } },
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Beschreibung" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Descripción" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Description" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "説明" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "描述" } }
  }
},
```

#### 3. Localization fixtures — required key + exclusion
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add `"Description"` to the `("App", [...])` list in `requiredKeys`, and since
the French value is byte-identical to English, add an exclusion entry (the
`nonEnglishValuesDifferFromEnglish` canary only skips whole keys):

```swift
ExclusionEntry(catalog: "App", key: "Description"),   // fr "Description" — same spelling as English
```

#### 4. Detail-view render canary
**File**: `CheckStitchTests/ChecklistDetailViewTests.swift`
**Action**: modify

The private environment-bound binding is not reachable headless (see Overview
deviation). Pin that the body still renders with a populated description using
the `ImageRenderer` pattern from `ViewRenderTests`, so a body-time regression
(e.g. a bad `TextField(axis:)` use) fails the suite.

```swift
/// The description field is added to the Items rows; this stages a real render
/// pass against an injected store (the binding itself is private and
/// environment-bound, so its read/write behaviour is pinned by the store tests).
@Test
func detailViewRendersItemsWithDescriptions() {
    let defaults = makeIsolatedDefaults()
    let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
    let checklist = store.create(name: "Groceries")
    store.addItem(to: checklist.id)
    let itemID = store.checklist(id: checklist.id)?.items.first?.id ?? UUID()
    store.updateItemDescription(checklistID: checklist.id, itemID: itemID, description: "2 litres")

    let view = ChecklistDetailView(checklistID: checklist.id).environment(store)
    #if os(macOS)
    #expect(ImageRenderer(content: view).nsImage != nil)
    #else
    #expect(ImageRenderer(content: view).uiImage != nil)
    #endif
}
```

Also add `"itemDescriptionField"` to the `String(describing:)` slot canary only
if the accessibility id surfaces there (it does not — identifiers live in the
body), so no change to the existing canaries beyond the new render test.

### Verification
#### Automated
- [x] `make test-unit` passes (includes the new render canary and the localization six-language suite)
- [x] `make build` (simulator) passes — the iOS body compiles with `axis: .vertical`
- [x] `make build-mac` passes
- [x] `grep -n '"Description"' CheckStitch/Localizable.xcstrings CheckStitchTests/LocalizationFixtures.swift` matches in both

#### Manual
- [ ] `make run` on the simulator: open a checklist, confirm each row shows a title field and a smaller multiline description field; typing a description does not disturb the title; the description persists after leaving and re-entering the screen (and after app relaunch)

---

## Phase 6: watchOS row — secondary caption line

### Changes

#### 1. Watch row body
**File**: `CheckStitchWatch/WatchChecklistDetailView.swift`
**Action**: modify

Presentation only; `visibleItems` keeps filtering on `isBlank` (Stage 1 helper).

```swift
List(visibleItems) { item in
    VStack(alignment: .leading) {
        Text(item.title)
        if item.hasDescription {
            Text(item.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

`visibleItems` and the `safeAreaInset` run button are unchanged. No new
localization key (description is user data, not a UI string).

### Verification
#### Automated
- [x] `make watch-build` passes
- [x] `bash scripts/test.sh` prints `gate: ok` (sim build → pre-boot → `make test` → `make build-mac` → `make watch-build` → shell tests → shellcheck)

#### Manual
- [ ] `bash scripts/run-watch.sh` on the paired watch: a described item shows the title plus a secondary caption; an item with no description shows only the title
- [ ] A blank-title item with a populated description stays hidden (still filtered by `isBlank`)
- [ ] A long description is clamped by SwiftUI's line limit without breaking the row

---

## Final checklist (all stages)

- [ ] `make test-unit` green after every stage
- [ ] `bash scripts/test.sh` prints `gate: ok`
- [ ] No `currentVersion` bump; `ChecklistCodec.currentVersion` is still `3`
- [ ] Legacy core `ChecklistCreator`/`ReminderCreating` untouched
- [ ] PR description notes the accepted risk: an older v3 build silently drops
      `description` on its next save (inherent to an additive field without a
      version bump)