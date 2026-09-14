# Implementation Plan

## Overview

`ChecklistItem` gains an optional relative-date offset (`Int?`: `0` = today,
`1` = tomorrow, negative = past, `nil` = no date). It is edited per item in
`ChecklistDetailView`, round-trips the versioned `checklists.v1` wire format
(envelope bumped to v3 with a non-restamping v2 read), and both reminder-creation
paths set a date-only `EKReminder.dueDateComponents` = local `today + offset`
via one pure Core function. Items without an offset keep today's no-date
behaviour.

## Decisions taken during planning (deviations from `structure.md`)

1. **`ChecklistCodec.Outcome.migratable` carries the whole envelope, not just
   `[Checklist]`** — `case migratable(from: Int, envelope: ChecklistEnvelope)`.
   A v2 payload carries `deviceID` and `tombstones`; routing v2 through the old
   `checklists:`-only payload would silently drop tombstones on store load and
   on remote reconcile (resurrecting deletions) and would zero the LWW
   `deviceID`. Still one case, no new `Outcome` cases. One existing test pattern
   updates.
2. **Watch accepts `.migratable(from: 2)`** (structure's recommended option).
3. **Stage 6 uses a buffered `ItemRow` subview instead of the unbuffered
   `relativeDateBinding`.** An unbuffered `Binding<String>` over `Int?` cannot
   represent `"-"` (the minus parses to `nil` → `get` returns `""`, erasing the
   keystroke), and `.numberPad` has no minus key, so negative offsets — which
   the design's end state documents — could never be entered. The row keeps a
   `@State` text buffer, commits the parsed value on every change (the store
   no-ops unchanged values), and therefore uses
   `.keyboardType(.numbersAndPunctuation)`. There is no `relativeDateBinding`.
4. **`duplicate(id:name:)` copies `relativeDate`.** The existing copy path
   rebuilds items from `title` only; without this the new field would vanish on
   duplicate. Necessary for the field to round-trip through an existing store
   mutation (not adjacent refactoring).
5. **`ChecklistCreator` gains a `calendar` parameter** alongside `now`, so the
   mirror's date assertions can be deterministic.

## Order of work

Stages are horizontal and strictly sequential: each lands code **and** its tests
green before the next starts. Nothing edits `project.pbxproj` or the
`checklists.v1` key name.

---

## Phase 1: Item model field + Codable round-trip

`ChecklistItem` gains the offset and round-trips it through JSON with no version
change involved.

### Changes

#### 1. `ChecklistItem` field, init, coding keys, codec
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add `relativeDate` last in the memberwise init (default `nil`, so existing call
sites are source-compatible), the stored property, the coding key, and the
lenient decode / eager encode.

```swift
public init(id: UUID = UUID(), title: String, modifiedAt: Date = .distantPast, revision: Int = 0, relativeDate: Int? = nil) {
    self.id = id
    self.title = title
    self.modifiedAt = modifiedAt
    self.revision = revision
    self.relativeDate = relativeDate
}

public let id: UUID
public var title: String
public var modifiedAt: Date
public var revision: Int
/// Days from today (0 = today, 1 = tomorrow, negative = past); `nil` = no date.
/// No time-of-day support. Not clamped — the arithmetic in
/// `ChecklistItem+DueDate.swift` is the only consumer.
public var relativeDate: Int?

private enum CodingKeys: String, CodingKey { case id, title, modifiedAt, revision, relativeDate }

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    // Absent in v2-and-earlier payloads and in `nil`-valued current payloads.
    relativeDate = try container.decodeIfPresent(Int.self, forKey: .relativeDate)
}

public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(modifiedAt, forKey: .modifiedAt)
    try container.encode(revision, forKey: .revision)
    // Write the key unconditionally, matching the "encoder writes every key"
    // invariant. `encode` on an `Int?` may omit the key depending on overload
    // resolution, so be explicit.
    if let relativeDate {
        try container.encode(relativeDate, forKey: .relativeDate)
    } else {
        try container.encodeNil(forKey: .relativeDate)
    }
}
```

### Verification

#### Automated
- [x] `make test-unit` passes with the new `ChecklistItemTests` cases below

#### Manual
- [ ] None (pure codable change, fully covered by unit tests)

### Tests

**File**: `CheckStitchTests/ChecklistItemTests.swift` (Swift Testing, existing
style: `struct` + `@Test`)

Add:

```swift
@Test(arguments: [nil, 0, 1, -3] as [Int?])
func relativeDateRoundTripsThroughJSON(_ offset: Int?) throws {
    let item = ChecklistItem(title: "one", relativeDate: offset)
    let decoded = try JSONDecoder().decode(ChecklistItem.self, from: JSONEncoder().encode(item))
    #expect(decoded.relativeDate == offset)
    #expect(decoded == item)
}

/// A v2 item object: no `relativeDate` key anywhere.
@Test
func itemWithoutRelativeDateKeyDecodesToNil() throws {
    let id = UUID().uuidString
    let data = Data(#"{"id":"\#(id)","title":"one"}"#.utf8)
    let decoded = try JSONDecoder().decode(ChecklistItem.self, from: data)
    #expect(decoded.relativeDate == nil)
}

/// The encoder always writes the key, as JSON `null` when there is no date.
@Test
func encodeAlwaysEmitsRelativeDateKey() throws {
    let data = try JSONEncoder().encode(ChecklistItem(title: "one"))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(object?.keys.contains("relativeDate") == true)
    #expect(object?["relativeDate"] is NSNull)
}
```

---

## Phase 2: Envelope v3 + version-aware migration (store, sync, watch)

`currentVersion` becomes 3; v2 payloads are accepted and re-encoded at v3
**without** restamping sync state and **without** losing tombstones/deviceID;
the watch accepts a v2 context as well as a v3 one.

### Changes

#### 1. `ChecklistCodec`: v3 constant, envelope-carrying `.migratable`, `case 2`
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

```swift
public enum ChecklistCodec {
    public static let currentVersion = 3
    ...
    public enum Outcome: Equatable {
        case loaded(ChecklistEnvelope)
        /// A known older version that can be upgraded in place. Carries the
        /// whole envelope so a v2 payload keeps its `deviceID` and `tombstones`.
        case migratable(from: Int, envelope: ChecklistEnvelope)
        case unsupportedVersion
        case unreadable
    }
```

In `classify`, add `case 2` and thread the envelope through `case 1`:

```swift
switch probe.version {
case currentVersion:
    return .loaded(try JSONDecoder().decode(ChecklistEnvelope.self, from: data))
case 2:
    // v2 already carries sync state: load it verbatim, never restamp.
    let previous = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
    return .migratable(from: 2, envelope: previous)
case 1:
    let legacy = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
    return .migratable(from: 1, envelope: legacy)
default:
    logger.error("Unsupported checklist payload version \(probe.version, privacy: .public); treating as empty")
    return .unsupportedVersion
}
```

And the convenience reader:

```swift
public static func decode(_ data: Data) -> [Checklist] {
    switch classify(data) {
    case .loaded(let envelope): return envelope.checklists
    case .migratable(_, let envelope): return envelope.checklists
    case .unsupportedVersion, .unreadable: return []
    }
}
```

#### 2. `ChecklistStore.init`: branch the migratable arm on `from`
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

```swift
case .migratable(let from, let legacy):
    if from == 1 {
        // v1 carried no sync state: stamp it (unchanged behaviour).
        self.checklists = legacy.checklists.map { $0.migrated(at: now()) }
    } else {
        // v2 (and later legacy versions) already carry sync state; load it
        // verbatim so a stored revision/modifiedAt is never restamped.
        self.checklists = legacy.checklists
    }
    self.tombstones = legacy.tombstones
    self.canOverwriteStoredPayload = true   // never stall migration
```

#### 3. `ChecklistStore.duplicate`: copy the offset
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

```swift
items: source.items.map {
    ChecklistItem(title: $0.title, modifiedAt: now(), revision: 1, relativeDate: $0.relativeDate)
},
```

#### 4. `ChecklistSyncService.reconcileNow`: remote v2 keeps id/tombstones, no restamp
**File**: `CheckStitch/ChecklistSyncService.swift`
**Action**: modify

```swift
case .migratable(let from, let legacy):
    if from == 1 {
        remote = ChecklistEnvelope(deviceID: "", checklists: legacy.checklists.map { $0.migrated(at: .distantPast) })
    } else {
        // v2 is currently-shaped: keep its deviceID (LWW tie-break) and
        // tombstones, and do not restamp revisions.
        remote = ChecklistEnvelope(
            deviceID: legacy.deviceID,
            checklists: legacy.checklists,
            tombstones: legacy.tombstones)
    }
```

Note `ChecklistEnvelope.init` defaults `version:` to `ChecklistCodec.currentVersion`,
which is required because `store.apply(remote:)` guards
`remote.version == currentVersion`.

#### 5. `WatchChecklistStore.receive`: accept `.migratable(from: 2)`
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

```swift
case .context(let data):
    // Malformed or future-version payloads leave the previous list intact.
    switch ChecklistCodec.classify(data) {
    case .loaded(let envelope):
        checklists = envelope.checklists
    case .migratable(let from, let envelope) where from >= 2:
        // v2 carries every v3 field; accept it rather than blanking the list.
        checklists = envelope.checklists
    default:
        break
    }
```

### Verification

#### Automated
- [x] `make test-unit` passes (fast loop)
- [x] `bash scripts/test.sh` passes before this phase's commit — `make watch-build`
      is the only leg that compiles the changed `ChecklistSync.swift` watch decoder
- [x] New codec/store/sync/watch tests below pass

#### Manual
- [ ] None (covered by unit suites; watch leg asserted by the gate's
      `make watch-build`)

### Tests

**File**: `CheckStitchTests/ChecklistCodecTests.swift` (XCTest style, `func testX`)

- Update `testLegacyV1PayloadIsClassifiedMigratable`: the pattern becomes
  `guard case .migratable(from: let version, envelope: let envelope) = outcome`
  and assertions read `envelope.checklists`.
- Add:

```swift
/// A v2 payload: it has sync state and tombstones, and must be accepted
/// verbatim (never restamped) when classified.
func testV2PayloadIsClassifiedMigratableWithTombstones() throws {
    let device = "device-a"
    let tombstone = ChecklistTombstone(
        checklistID: UUID(), itemID: nil, deletedAt: Date(timeIntervalSince1970: 42), revision: 3)
    let envelope = ChecklistEnvelope(
        version: 2, deviceID: device,
        checklists: [Checklist(name: "Groceries", modifiedAt: Date(timeIntervalSince1970: 7), revision: 5)],
        tombstones: [tombstone])

    XCTAssertEqual(ChecklistCodec.classify(try ChecklistCodec.encode(envelope)),
                   .migratable(from: 2, envelope: envelope))
}

func testCurrentVersionPayloadIsLoaded() throws {
    let envelope = ChecklistEnvelope(deviceID: "d", checklists: [Checklist(name: "x")])
    XCTAssertEqual(ChecklistCodec.classify(try ChecklistCodec.encode(envelope)), .loaded(envelope))
}

func testVersionFourIsUnsupported() {
    let data = Data(#"{"version":4,"checklists":[]}"#.utf8)
    XCTAssertEqual(ChecklistCodec.classify(data), .unsupportedVersion)
}
```

**File**: `CheckStitchTests/ChecklistStoreTests.swift` (XCTest)

- Rename `testNewPayloadIsVersionTwo` → `testNewPayloadIsVersionThree` and assert
  `stored.version == 3` (schema-version assertion).
- Add:

```swift
/// A stored v2 payload has real sync state. It must load with its revision,
/// timestamp and tombstones intact, stay writable, and never be restamped.
func testV2PayloadLoadsVerbatimWithoutRestamping() throws {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

    let itemID = UUID()
    let modifiedAt = Date(timeIntervalSince1970: 1_234)
    let payload = ChecklistEnvelope(
        version: 2,
        deviceID: "remote-device",
        checklists: [Checklist(
            name: "Groceries",
            items: [ChecklistItem(id: itemID, title: "Milk", modifiedAt: modifiedAt, revision: 7)],
            modifiedAt: modifiedAt,
            revision: 9)],
        tombstones: [ChecklistTombstone(
            checklistID: UUID(), itemID: nil, deletedAt: modifiedAt, revision: 2)])
    suite.defaults.set(try ChecklistCodec.encode(payload), forKey: key)

    let store = makeStore(defaults: suite.defaults)
    XCTAssertTrue(store.canAcceptRemoteChanges, "a migrated v2 payload stays writable")
    XCTAssertEqual(store.checklists.first?.revision, 9, "v2 revisions must not be restamped")
    XCTAssertEqual(store.checklists.first?.modifiedAt, modifiedAt)
    XCTAssertEqual(store.checklists.first?.items.first?.revision, 7)
    XCTAssertEqual(store.tombstones.count, 1, "v2 tombstones must survive migration")

    // Persist and reload: still not restamped.
    store.create()
    let reloaded = makeStore(defaults: suite.defaults)
    XCTAssertEqual(reloaded.checklists.first(where: { $0.name == "Groceries" })?.revision, 9)
    XCTAssertEqual(reloaded.tombstones.count, 1)
}
```

**File**: `CheckStitchTests/ChecklistSyncServiceTests.swift` (Swift Testing)

- Add:

```swift
@Test
func cloudV2PayloadIsAbsorbedWithoutRestampingOrTombstoneLoss() async throws {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

    let store = makeStore(defaults: suite.defaults)
    let remoteID = UUID()
    let checklistID = UUID()
    let tombstone = ChecklistTombstone(
        checklistID: checklistID, itemID: nil, deletedAt: Date(timeIntervalSince1970: 99), revision: 2)
    let payload = ChecklistEnvelope(
        version: 2,
        deviceID: "remote-device",
        checklists: [Checklist(id: remoteID, name: "Remote", modifiedAt: Date(timeIntervalSince1970: 50), revision: 4)],
        tombstones: [tombstone])
    let sync = InMemoryChecklistSync(stored: try ChecklistCodec.encode(payload))
    let service = makeService(sync: sync, store: store)

    let outcome = await service.reconcile()

    #expect(outcome == .synced)
    #expect(store.checklists.first(where: { $0.id == remoteID })?.revision == 4, "v2 revisions are not restamped")
    #expect(store.tombstones.contains(tombstone), "v2 tombstones are not dropped")
}
```

**File**: `CheckStitchTests/WatchChecklistStoreTests.swift` (Swift Testing)

- Add:

```swift
@Test
func v2ContextStillPopulatesTheList() throws {
    let transport = FakeChecklistSyncTransport()
    let store = WatchChecklistStore(transport: transport)
    store.start()

    let expected = [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", relativeDate: 1)])]
    transport.deliver(.context(try ChecklistCodec.encode(
        ChecklistEnvelope(version: 2, deviceID: "phone", checklists: expected))))

    #expect(store.checklists == expected)
}
```

---

## Phase 3: Pure offset → date-only arithmetic

One dependency-free function in Core turns an offset into a date-only
`DateComponents?`. This is the single source of truth for both reminder paths.

### Changes

#### 1. New Core extension
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistItem+DueDate.swift`
**Action**: create

```swift
import Foundation

extension ChecklistItem {
    /// The date-only due-date components for a reminder, or `nil` when the item
    /// carries no relative date. `0` is today, `1` tomorrow, negatives are past
    /// days. Time components are deliberately absent: CheckStitch has no
    /// time-of-day support.
    ///
    /// `calendar` is injectable so tests can pin a time zone; production callers
    /// use the device-local `.current`, matching the SingleThread precedent.
    public func dueDateComponents(today: Date, calendar: Calendar = .current) -> DateComponents? {
        guard let relativeDate else { return nil }
        guard let target = calendar.date(
            byAdding: .day,
            value: relativeDate,
            to: calendar.startOfDay(for: today)
        ) else { return nil }
        return calendar.dateComponents([.year, .month, .day], from: target)
    }
}
```

### Verification

#### Automated
- [x] `make test-unit` passes with the new `ChecklistItemDateTests`

#### Manual
- [ ] None

### Tests

**File**: `CheckStitchTests/ChecklistItemDateTests.swift` (new, Swift Testing)
**Action**: create

```swift
@testable import CheckStitchCore
import Foundation
import Testing

struct ChecklistItemDateTests {
    /// Fixed calendar + zone so the arithmetic is deterministic everywhere.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test
    func noOffsetYieldsNoDate() {
        #expect(ChecklistItem(title: "x").dueDateComponents(today: date(2026, 3, 10), calendar: calendar) == nil)
    }

    @Test(arguments: [(0, 10), (1, 11), (-1, 9)])
    func offsetMovesWholeDays(_ offset: Int, _ expectedDay: Int) {
        let components = ChecklistItem(title: "x", relativeDate: offset)
            .dueDateComponents(today: date(2026, 3, 10), calendar: calendar)
        #expect(components == DateComponents(year: 2026, month: 3, day: expectedDay))
    }

    @Test
    func offsetCrossesAMonthBoundary() {
        let components = ChecklistItem(title: "x", relativeDate: 1)
            .dueDateComponents(today: date(2026, 1, 31), calendar: calendar)
        #expect(components == DateComponents(year: 2026, month: 2, day: 1))
    }

    @Test
    func offsetCrossesAYearBoundary() {
        let components = ChecklistItem(title: "x", relativeDate: -1)
            .dueDateComponents(today: date(2026, 1, 1), calendar: calendar)
        #expect(components == DateComponents(year: 2025, month: 12, day: 31))
    }

    /// Just before local midnight still yields that local day (`startOfDay`).
    @Test
    func lateInTheDayStillYieldsThatDay() {
        let components = ChecklistItem(title: "x", relativeDate: 0)
            .dueDateComponents(today: date(2026, 3, 10, 23, 59), calendar: calendar)
        #expect(components == DateComponents(year: 2026, month: 3, day: 10))
    }

    @Test
    func resultCarriesNoTimeComponents() {
        let components = ChecklistItem(title: "x", relativeDate: 2)
            .dueDateComponents(today: date(2026, 3, 10), calendar: calendar)
        #expect(components?.hour == nil)
        #expect(components?.minute == nil)
        #expect(components?.second == nil)
    }
}
```

---

## Phase 4: Store mutation API for the offset

The store gains an offset mutator shaped exactly like `updateItem(title:)`, with
a no-op guard on unchanged values so partial-input retries cannot manufacture
LWW wins.

### Changes

#### 1. `updateItem(..., relativeDate:)` overload
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify (add directly below the existing `title:` overload)

```swift
/// Sets (or clears) an item's relative-date offset. Distinct label, so it sits
/// beside `updateItem(checklistID:itemID:title:)` without ambiguity. An
/// unchanged value is a no-op — this is what stops a text field re-committing
/// the same parse from bumping `revision` and winning a spurious LWW round.
func updateItem(checklistID: UUID, itemID: UUID, relativeDate: Int?) {
    guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
          let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
    else { return }
    guard checklists[checklistIndex].items[itemIndex].relativeDate != relativeDate else { return }
    checklists[checklistIndex].items[itemIndex].relativeDate = relativeDate
    checklists[checklistIndex].items[itemIndex].revision += 1
    checklists[checklistIndex].items[itemIndex].modifiedAt = now()
    scheduleSave()
}
```

The existing `updateItem(..., title:)` is untouched.

### Verification

#### Automated
- [x] `make test-unit` passes

#### Manual
- [ ] None

### Tests

**File**: `CheckStitchTests/ChecklistStoreTests.swift` (XCTest, existing `makeStore`
helper has `textEditDelay: nil`)

```swift
func testUpdateItemRelativeDatePersists() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

    let store = makeStore(defaults: suite.defaults)
    let created = store.create()
    store.addItem(to: created.id)
    guard let item = store.checklist(id: created.id)?.items.first else {
        XCTFail("expected the added item")
        return
    }

    store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 3)

    let reloaded = makeStore(defaults: suite.defaults)
    XCTAssertEqual(reloaded.checklist(id: created.id)?.items.first?.relativeDate, 3)
}

func testUpdateItemRelativeDateClearsToNil() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

    let store = makeStore(defaults: suite.defaults)
    let created = store.create()
    store.addItem(to: created.id)
    guard let item = store.checklist(id: created.id)?.items.first else { return }
    store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 3)

    store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: nil)

    XCTAssertNil(store.checklist(id: created.id)?.items.first?.relativeDate)
}

func testUpdateItemRelativeDateNoOpsWhenUnchanged() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

    let store = makeStore(defaults: suite.defaults)
    let created = store.create()
    store.addItem(to: created.id)
    guard let item = store.checklist(id: created.id)?.items.first else { return }
    store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)
    let revision = store.checklist(id: created.id)?.items.first?.revision

    var changes = 0
    store.onChange = { changes += 1 }
    store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)

    XCTAssertEqual(store.checklist(id: created.id)?.items.first?.revision, revision)
    XCTAssertEqual(changes, 0, "an unchanged value must not schedule a save or push")
}

func testUpdateItemRelativeDateIgnoresUnknownIDs() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

    let store = makeStore(defaults: suite.defaults)
    let created = store.create()
    var changes = 0
    store.onChange = { changes += 1 }

    store.updateItem(checklistID: UUID(), itemID: UUID(), relativeDate: 1)
    store.updateItem(checklistID: created.id, itemID: UUID(), relativeDate: 1)

    XCTAssertEqual(changes, 0)
}

func testRelativeDateEditsAreCoalescedUntilFlush() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

    let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: .milliseconds(50))
    let created = store.create()
    store.addItem(to: created.id)
    guard let item = store.checklist(id: created.id)?.items.first else { return }

    store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 1)
    store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)

    XCTAssertEqual(store.checklist(id: created.id)?.items.first?.relativeDate, 2)
    XCTAssertNil(makeStore(defaults: suite.defaults).checklist(id: created.id)?.items.first?.relativeDate)

    store.flushPendingSave()
    XCTAssertEqual(makeStore(defaults: suite.defaults).checklist(id: created.id)?.items.first?.relativeDate, 2)
}
```

Also extend `testDuplicatePersistsAcrossReload` (or add a sibling) to set a
relative date before duplicating and assert the copy carries it:

```swift
func testDuplicateCopiesRelativeDate() {
    let suite = makeDefaults()
    defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

    let store = makeStore(defaults: suite.defaults)
    let source = store.create(name: "Groceries")
    store.addItem(to: source.id)
    guard let item = store.checklist(id: source.id)?.items.first else { return }
    store.updateItem(checklistID: source.id, itemID: item.id, relativeDate: 2)

    let copy = store.duplicate(id: source.id, name: "Groceries copy")

    XCTAssertEqual(copy?.items.first?.relativeDate, 2)
}
```

---

## Phase 5: Reminder creation paths (live + core mirror)

Both paths pass a date-only `DateComponents` computed by Phase 3 to the
EventKit seam. The live path stays logic-free (a nil-guarded property set); the
mirror is exercised end-to-end through the spy.

### Changes

#### 1. `ReminderCreating` seam
**File**: `CheckStitchCore/Sources/CheckStitchCore/ReminderCreating.swift`
**Action**: modify

```swift
public protocol ReminderCreating: Sendable {
    func requestAccess() async throws -> Bool
    func create(title: String, dueDateComponents: DateComponents?) async throws
}
```

```swift
public func create(title: String, dueDateComponents: DateComponents?) async throws {
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    reminder.calendar = eventStore.defaultCalendarForNewReminders()
    if let dueDateComponents {
        reminder.dueDateComponents = dueDateComponents
    }
    // watchOS EventKit is read-only; the watch never reaches this adapter.
    #if !os(watchOS)
        try eventStore.save(reminder, commit: true)
    #endif
}
```

#### 2. `ChecklistCreator`: inject `now` + `calendar`, compute per item
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`
**Action**: modify

```swift
public init(reminders: ReminderCreating,
            now: @escaping @Sendable () -> Date = Date.init,
            calendar: Calendar = .current) {
    self.reminders = reminders
    self.now = now
    self.calendar = calendar
}

public func create(from items: [ChecklistItem]) async -> ChecklistCreationOutcome {
    do {
        guard try await reminders.requestAccess() else { return .permissionDenied }
        var created = 0
        let today = now()
        for item in items where !item.isBlank {
            try await reminders.create(
                title: item.title,
                dueDateComponents: item.dueDateComponents(today: today, calendar: calendar))
            created += 1
        }
        return .created(count: created)
    } catch {
        return .failed(error.localizedDescription)
    }
}

private let reminders: ReminderCreating
private let now: @Sendable () -> Date
private let calendar: Calendar
```

`ChecklistViewModel` needs no change (defaults apply); `ChecklistViewModelTests`
needs no assertion change once the spy shim lands.

#### 3. Live path: set the date, nil-guarded, one line
**File**: `CheckStitch/ChecklistReminders.swift`
**Action**: modify

```swift
let reminder = EKReminder(eventStore: eventStore)
reminder.title = item.title
reminder.calendar = eventStore.defaultCalendarForNewReminders()
if let dueDateComponents = item.dueDateComponents(today: Date()) {
    reminder.dueDateComponents = dueDateComponents
}
try eventStore.save(reminder, commit: true)
```

No other branching is added: the offset → date arithmetic lives only in
Phase 3.

#### 4. `SpyReminderCreator`: record components, keep `createdTitles` as a shim
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

```swift
/// Records every created reminder's title and date. `createdTitles` remains a
/// computed shim so existing assertions (Creator + ViewModel suites) stay valid.
private(set) var createdItems: [(title: String, dueDateComponents: DateComponents?)] = []
var createdTitles: [String] { createdItems.map { $0.title } }

func create(title: String, dueDateComponents: DateComponents?) async throws {
    if let createError { throw createError }
    onCreate?()
    createdItems.append((title: title, dueDateComponents: dueDateComponents))
}
```

### Verification

#### Automated
- [x] `make test-unit` passes
- [ ] `bash scripts/test.sh` passes (compiles both reminder paths + watch leg)

#### Manual
- [ ] `make run`, create a checklist with one item titled `today` (offset `0`),
      one `tomorrow` (offset `1`) and one unnumbered item, run the checklist,
      and confirm in Reminders that the first two show today/tomorrow and the
      third has no date

### Tests

**File**: `CheckStitchTests/ChecklistCreatorTests.swift` (Swift Testing)

```swift
/// Fixed, UTC gregorian calendar plus a fixed "today" so the components are
/// exact. Built as locals (a `Date` is `Sendable`) rather than captured through
/// `self`, because the creator's `now` closure must be `@Sendable`.
@Test
func relativeDatesCarryThroughToTheSeam() async {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
    let spy = SpyReminderCreator()
    let creator = ChecklistCreator(reminders: spy, now: { today }, calendar: calendar)
    let items = [
        ChecklistItem(title: "a", relativeDate: 0),
        ChecklistItem(title: "b", relativeDate: 1),
        ChecklistItem(title: "c"),
    ]

    let outcome = await creator.create(from: items)

    #expect(outcome == .created(count: 3))
    #expect(spy.createdItems.map { $0.title } == ["a", "b", "c"])
    #expect(spy.createdItems[0].dueDateComponents == DateComponents(year: 2026, month: 3, day: 10))
    #expect(spy.createdItems[1].dueDateComponents == DateComponents(year: 2026, month: 3, day: 11))
    #expect(spy.createdItems[2].dueDateComponents == nil)
}

@Test
func blankItemsAreStillSkippedWhenTheyCarryDates() async {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
    let spy = SpyReminderCreator()
    let creator = ChecklistCreator(reminders: spy, now: { today }, calendar: calendar)

    let outcome = await creator.create(from: [
        ChecklistItem(title: "  ", relativeDate: 3),
        ChecklistItem(title: "a", relativeDate: -1),
    ])

    #expect(outcome == .created(count: 1))
    #expect(spy.createdItems.map { $0.title } == ["a"])
    #expect(spy.createdItems[0].dueDateComponents == DateComponents(year: 2026, month: 3, day: 9))
}
```

**File**: `CheckStitchTests/EventKitReminderCreatorTests.swift` (Swift Testing)

Extend the crash-canary to prove `dueDateComponents` is readable on a reminder
built from the injected store (no `save`):

```swift
@Test
func eventKitReminderCarriesDateOnlyDueComponents() {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.dueDateComponents = DateComponents(year: 2026, month: 3, day: 10)
    #expect(reminder.dueDateComponents?.year == 2026)
    #expect(reminder.dueDateComponents?.month == 3)
    #expect(reminder.dueDateComponents?.day == 10)
    #expect(reminder.dueDateComponents?.hour == nil)
}
```

**File**: `CheckStitchTests/ChecklistViewModelTests.swift`

- No assertion changes: `spy.createdTitles` is now a computed shim.

---

## Phase 6: Detail-row date field (buffered)

One date control per item row, backed by a per-row text buffer so partial input
(including a leading `-`) survives typing, committed to Phase 4's store API.

### Changes

#### 1. `ItemRow` subview + row wiring
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Replace the single `TextField` in `Section("Items")` with an `ItemRow`:

```swift
Section("Items") {
    ForEach(checklist.items) { item in
        ItemRow(
            title: titleBinding(checklistID: checklistID, itemID: item.id),
            relativeDate: item.relativeDate
        ) { newValue in
            store.updateItem(checklistID: checklistID, itemID: item.id, relativeDate: newValue)
        }
    }
    .onDelete { offsets in
        store.removeItems(from: checklistID, at: offsets)
    }
}
```

Add the row type at file scope (internal, so tests can describe it):

```swift
/// One item row: title plus an optional relative-date field.
///
/// The date field keeps its own text buffer. An unbuffered `Binding<String>`
/// over `Int?` cannot represent a half-typed `"-"`: it parses to `nil`, and
/// `get` would immediately render `""`, erasing the minus. Buffering also lets
/// a typed `""`/`"-"` survive until `-5` is complete. Committing on every
/// change is safe because `ChecklistStore.updateItem(…, relativeDate:)` no-ops
/// an unchanged value.
struct ItemRow: View {
    let title: Binding<String>
    let relativeDate: Int?
    let commitRelativeDate: (Int?) -> Void

    @State private var draftDate = ""
    @State private var didLoadDraft = false

    var body: some View {
        HStack {
            TextField("Item", text: title)
            TextField("Days", text: $draftDate)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .accessibilityIdentifier("itemRelativeDateField")
                .onChange(of: draftDate) { _, newValue in
                    commitRelativeDate(Self.parse(newValue))
                }
        }
        .onAppear {
            guard !didLoadDraft else { return }
            draftDate = Self.format(relativeDate)
            didLoadDraft = true
        }
    }

    /// Unparseable text (including an in-progress `"-"`) means "no date".
    static func parse(_ text: String) -> Int? { Int(text) }

    /// `nil` renders as the empty field.
    static func format(_ value: Int?) -> String { value.map(String.init) ?? "" }
}
```

Notes:
- `.numbersAndPunctuation`, not `.numberPad` — the number pad has no minus key.
- Committing inside `onAppear`'s seeding (if SwiftUI fires `onChange` for it) is
  harmless: the parsed value equals the stored one, so the store no-ops.
- The checklist name field's buffered `draftName` precedent is the model here.

### Verification

#### Automated
- [ ] `make test-unit` passes
- [ ] `bash scripts/test.sh` passes — this phase compiles the real UI, so the
      gate (not just the fast loop) is required

#### Manual
- [ ] `make run`; open a checklist; type `1` in an item's Days field → the
      value sticks; change it to `-2` (minus is typeable) → sticks; clear the
      field → date cleared; background the app and relaunch → the value persists
- [ ] Reminder check: run the checklist and confirm the same item shows the
      expected today-relative date in Reminders

### Tests

**File**: `CheckStitchTests/ChecklistDetailViewTests.swift` (Swift Testing,
`@MainActor`; `String(describing:)`-based, since bodies can't be staged headless)

```swift
/// The date control's value graph: the row owns a text buffer, so a partial
/// `"-"` can survive long enough to be completed. The parse/format pair is pure
/// and asserted directly; commit behaviour is covered by the store suite.
@Test
func itemRowBuffersItsDateText() {
    let described = String(describing: ItemRow(
        title: .constant("Milk"), relativeDate: 1, commitRelativeDate: { _ in }))
    #expect(described.contains("relativeDate"))
    #expect(described.contains("_draftDate"))
}

@Test(arguments: [
    ("", Int?.none), ("-", Int?.none), ("abc", Int?.none),
    ("0", Int?.some(0)), ("-3", Int?.some(-3)), ("12", Int?.some(12)),
])
func itemRowParsesDateText(_ text: String, _ expected: Int?) {
    #expect(ItemRow.parse(text) == expected)
}

@Test(arguments: [(Int?.none, ""), (Int?.some(0), "0"), (Int?.some(-3), "-3")])
func itemRowFormatsMissingDatesAsEmpty(_ value: Int?, _ expected: String) {
    #expect(ItemRow.format(value) == expected)
}
```

The existing three tests in this suite are unchanged.

---

## Testing Checkpoints

- **After Phase 1**: `make test-unit` — item round-trip incl. absent-key decode + `null` emit.
- **After Phase 2**: `make test-unit` + `bash scripts/test.sh` — v3 stored; v2 loads verbatim (revision/timestamp/tombstones intact); watch compiles and accepts v2.
- **After Phase 3**: `make test-unit` — deterministic offsets incl. month/year boundaries and `startOfDay`.
- **After Phase 4**: `make test-unit` — set/clear/no-op/no-op-unknown/coalesce; duplicate copies the offset.
- **After Phase 5**: `make test-unit` + gate + manual Reminders check — both paths carry the computed date.
- **After Phase 6**: gate green + manual typing check. Only then is VAR-1000 done.

## Cross-Cutting Notes

- **The live reminder path is not unit-testable** (fresh `EKEventStore`, real
  permissions). Its assurance is Phase 3's tested arithmetic plus Phase 5's
  parity through `SpyReminderCreator`; the added live code is a single
  nil-guarded assignment.
- **Never restamp v2**: the explicit anti-restamp tests in Phase 2 are the guard
  against a future refactor folding `from == 2` into the v1 `migrated(at:)` arm.
- **`EKReminder` holds a weak store reference**; every EventKit-touching test
  uses `sharedTestEventStore`, and `EventKitReminderCreator.create` is never
  called from tests (it would `save` without permission).
- **Item merge is whole-item LWW**: the new field lives or dies with the item
  revision as a unit; no field-level merge is added.
- **Watch UI is unchanged** (titles only); only its decoder gained the v2 arm.
- **No changes** to the `checklists.v1` / KVS key names, tombstones GC,
  `AppEnvironment`, `Checklist.written(at:)`, or the UI smoke test.

## Files Touched

| File | Action | Phase |
|---|---|---|
| `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` | modify | 1, 2 |
| `CheckStitchTests/ChecklistItemTests.swift` | modify | 1 |
| `CheckStitchTests/ChecklistCodecTests.swift` | modify | 2 |
| `CheckStitch/ChecklistStore.swift` | modify | 2, 4 |
| `CheckStitch/ChecklistSyncService.swift` | modify | 2 |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift` | modify | 2 |
| `CheckStitchTests/ChecklistStoreTests.swift` | modify | 2, 4 |
| `CheckStitchTests/ChecklistSyncServiceTests.swift` | modify | 2 |
| `CheckStitchTests/WatchChecklistStoreTests.swift` | modify | 2 |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistItem+DueDate.swift` | create | 3 |
| `CheckStitchTests/ChecklistItemDateTests.swift` | create | 3 |
| `CheckStitchCore/Sources/CheckStitchCore/ReminderCreating.swift` | modify | 5 |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift` | modify | 5 |
| `CheckStitch/ChecklistReminders.swift` | modify | 5 |
| `CheckStitchTests/TestFixtures.swift` | modify | 5 |
| `CheckStitchTests/ChecklistCreatorTests.swift` | modify | 5 |
| `CheckStitchTests/EventKitReminderCreatorTests.swift` | modify | 5 |
| `CheckStitch/ChecklistDetailView.swift` | modify | 6 |
| `CheckStitchTests/ChecklistDetailViewTests.swift` | modify | 6 |

No `project.pbxproj` edit: new files are picked up by
`PBXFileSystemSynchronizedRootGroup` (app target) and SPM (Core package).