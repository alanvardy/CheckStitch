# Implementation Plan

## Overview

Replace the whole-item LWW copy in `ChecklistMerge.mergedItems` with a
per-axis merge: `title`, `description` and `relativeDate` each get their own
`*Revision`/`*ModifiedAt` clock, stamped only by their own mutator and resolved
with the existing `wins` comparator. Six additive optional keys ride the
current v4 envelope (absent keys seed from the item's coarse clock on decode),
so legacy payloads keep today's semantics with no version bump.

---

## Phase 1: Walking skeleton — concurrent title + description edits both survive

A title edit on one device and a description edit on another against the same
item both survive the merge, in either argument order, through model → codec →
merge → store → sync. Legacy payloads without the new keys still load and merge
with today's semantics.

### Changes

#### 1. Per-field clocks on `ChecklistItem`
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add four stored properties (after `relativeDate`), extend `CodingKeys`, extend
`init` with trailing optional params that seed from the coarse clock, seed in
`init(from:)`, and encode all four unconditionally.

```swift
public init(
    id: UUID = UUID(), title: String, description: String = "",
    modifiedAt: Date = .distantPast, revision: Int = 0, relativeDate: Int? = nil,
    titleRevision: Int? = nil, titleModifiedAt: Date? = nil,
    descriptionRevision: Int? = nil, descriptionModifiedAt: Date? = nil
) {
    self.id = id
    self.title = title
    self.description = description
    self.modifiedAt = modifiedAt
    self.revision = revision
    self.relativeDate = relativeDate
    // A fresh record (or a legacy payload) attributes its last whole-item edit
    // to every field, so a nil field clock seeds from the coarse clock.
    self.titleRevision = titleRevision ?? revision
    self.titleModifiedAt = titleModifiedAt ?? modifiedAt
    self.descriptionRevision = descriptionRevision ?? revision
    self.descriptionModifiedAt = descriptionModifiedAt ?? modifiedAt
}

public let id: UUID
public var title: String
public var description: String
public var modifiedAt: Date
public var revision: Int
public var relativeDate: Int?
/// Per-field sync identity: each editable field carries its own clock so a
/// title edit and a description edit from two devices are independent.
public var titleRevision: Int
public var titleModifiedAt: Date
public var descriptionRevision: Int
public var descriptionModifiedAt: Date

private enum CodingKeys: String, CodingKey {
    case id, title, description, modifiedAt, revision, relativeDate
    case titleRevision, titleModifiedAt, descriptionRevision, descriptionModifiedAt
}
```

In `init(from:)`, after `revision`/`relativeDate` are decoded (order matters —
the seeds read `revision`/`modifiedAt`):

```swift
// Additive optional keys: absent in pre-upgrade payloads, so seed each field
// clock from the item's coarse clock (today's semantics on first contact).
titleRevision = try container.decodeIfPresent(Int.self, forKey: .titleRevision) ?? revision
titleModifiedAt = try container.decodeIfPresent(Date.self, forKey: .titleModifiedAt) ?? modifiedAt
descriptionRevision = try container.decodeIfPresent(Int.self, forKey: .descriptionRevision) ?? revision
descriptionModifiedAt = try container.decodeIfPresent(Date.self, forKey: .descriptionModifiedAt) ?? modifiedAt
```

In `encode(to:)`, after `relativeDate`, write all four unconditionally:

```swift
try container.encode(titleRevision, forKey: .titleRevision)
try container.encode(titleModifiedAt, forKey: .titleModifiedAt)
try container.encode(descriptionRevision, forKey: .descriptionRevision)
try container.encode(descriptionModifiedAt, forKey: .descriptionModifiedAt)
```

#### 2. Seed field clocks in `migrated(at:)`
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

v1 restamping must seed the field clocks to the same values as the item's
upgraded coarse clock. In the item map inside `migrated(at:)`:

```swift
copy.items = copy.items.map { item in
    var upgraded = item
    upgraded.modifiedAt = date
    upgraded.revision = max(upgraded.revision, 1)
    upgraded.titleRevision = upgraded.revision
    upgraded.titleModifiedAt = date
    upgraded.descriptionRevision = upgraded.revision
    upgraded.descriptionModifiedAt = date
    return upgraded
}
```

`seededOrder()` (v2) needs **no** change: v2 items decode through
`init(from:)`, which already seeds the field clocks from their coarse clock.

#### 3. Per-field resolution in `mergedItems`
**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: modify

Add the `fieldWins` wrapper next to `wins`, and replace the whole-item
`result[index] = remoteItem` with per-field resolution. Start from the local
item, resolve each field independently, then take the coarse clock from the
whole-item winner.

```swift
private static func fieldWins(
    revision: Int, date: Date, device: String,
    overRevision: Int, overDate: Date, overDevice: String
) -> Bool {
    wins(revision: revision, date: date, device: device,
         overRevision: overRevision, overDate: overDate, overDevice: overDevice)
}
```

```swift
let localItem = result[index]
var merged = localItem
// Coarse clock: always the whole-item winner's, so the tombstone invariant
// (`removed.revision + 1`) keeps holding.
if wins(revision: remoteItem.revision, date: remoteItem.modifiedAt, device: remoteDevice,
        overRevision: localItem.revision, overDate: localItem.modifiedAt, overDevice: localDevice) {
    merged.revision = remoteItem.revision
    merged.modifiedAt = remoteItem.modifiedAt
}
if fieldWins(revision: remoteItem.titleRevision, date: remoteItem.titleModifiedAt, device: remoteDevice,
             overRevision: localItem.titleRevision, overDate: localItem.titleModifiedAt, overDevice: localDevice) {
    merged.title = remoteItem.title
    merged.titleRevision = remoteItem.titleRevision
    merged.titleModifiedAt = remoteItem.titleModifiedAt
}
if fieldWins(revision: remoteItem.descriptionRevision, date: remoteItem.descriptionModifiedAt, device: remoteDevice,
             overRevision: localItem.descriptionRevision, overDate: localItem.descriptionModifiedAt, overDevice: localDevice) {
    merged.description = remoteItem.description
    merged.descriptionRevision = remoteItem.descriptionRevision
    merged.descriptionModifiedAt = remoteItem.descriptionModifiedAt
}
result[index] = merged
```

#### 4. Per-field stamping in the store mutators
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

`create`/`duplicate`/`addItem` need **no** code change — they build
`ChecklistItem` through the public init, which now seeds every field clock
from `modifiedAt`/`revision`. Only the two text mutators change; each stamps
**only its own** field clock, using a single `now()` sample.

`updateItem(checklistID:itemID:title:)`:

```swift
let revisedAt = now()
checklists[checklistIndex].items[itemIndex].title = title
checklists[checklistIndex].items[itemIndex].revision += 1
checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
checklists[checklistIndex].items[itemIndex].titleRevision = checklists[checklistIndex].items[itemIndex].revision
checklists[checklistIndex].items[itemIndex].titleModifiedAt = revisedAt
scheduleSave()
```

`updateItemDescription(checklistID:itemID:description:)` mirrors it with
`descriptionRevision`/`descriptionModifiedAt`.

#### 5. Merge-test fixtures and the two replaced tests
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

Extend the `item(...)` fixture with the field-clock params (default `nil`, so
all existing calls are unchanged):

```swift
@MainActor
func item(id: UUID, title: String, description: String = "", revision: Int,
          modifiedAt: Date = .distantPast, relativeDate: Int? = nil,
          titleRevision: Int? = nil, titleModifiedAt: Date? = nil,
          descriptionRevision: Int? = nil, descriptionModifiedAt: Date? = nil) -> ChecklistItem {
    ChecklistItem(id: id, title: title, description: description, modifiedAt: modifiedAt,
                  revision: revision, relativeDate: relativeDate,
                  titleRevision: titleRevision, titleModifiedAt: titleModifiedAt,
                  descriptionRevision: descriptionRevision, descriptionModifiedAt: descriptionModifiedAt)
}
```

Delete `sameItemEditedOnBothDevicesUsesLWW` and
`descriptionFollowsTheWholeItemLWinner`. Add:

- `titleAndDescriptionEditsOnDifferentDevicesBothSurvive` — device A edits
  `title` (coarse revision 2), device B edits `description` (coarse revision 1);
  assert merged `title == A's`, `description == B's`, `revision == 2` (whole-item
  winner), and that the loser's field clock survives (merge the result again
  with itself → `contentEquals` no-op).
- `titleAndDescriptionEditsOnDifferentDevicesBothSurviveReversed` — identical
  fixture with `local`/`remote` swapped; assert the same title/description and
  that the two argument orders produce equal `checklists`.
- `sameFieldEditsStillResolveByFieldLWW` — title edited on both devices; the
  higher `titleRevision` wins (preserves the coverage the deleted test gave).
- `tombstoneBeatsANewerFieldClock` — an item with a newer per-field clock on
  each side still disappears when the remote envelope tombstoned its id.

Fields are set explicitly through the fixture, e.g. device A's item:
`item(id: itemID, title: "A title", revision: 3, modifiedAt: Date(timeIntervalSince1970: 30), titleRevision: 3, titleModifiedAt: Date(timeIntervalSince1970: 30))`.

#### 6. Codec tests
**File**: `CheckStitchTests/ChecklistCodecTests.swift`
**Action**: modify

Add:

- `testFieldClocksSurviveEnvelopeRoundTrip` — encode an envelope whose item has
  explicit per-field clocks; `classify` is `.loaded`; decode an item whose
  `titleRevision`/`titleModifiedAt`/`descriptionRevision`/`descriptionModifiedAt`
  match what was written; the raw bytes contain all four key strings.
- `testItemWithoutFieldClocksSeedsFromCoarseClock` — a v4 raw-JSON payload with
  an item carrying `revision`/`modifiedAt` but none of the four keys classifies
  `.loaded`, and its decoded item seeds
  `titleRevision == descriptionRevision == revision` and both `*ModifiedAt ==
  modifiedAt`. Follow `testItemWithoutDescriptionClassifiesLoadedAsEmpty`'s
  exact shape:

```swift
let data = Data(#"{"version":4,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk","revision":3,"modifiedAt":100}]}]}"#.utf8)
guard case .loaded(let envelope) = ChecklistCodec.classify(data) else { XCTFail(...); return }
let item = try XCTUnwrap(envelope.checklists.first?.items.first)
XCTAssertEqual(item.titleRevision, 3)
XCTAssertEqual(item.descriptionRevision, 3)
XCTAssertEqual(item.titleModifiedAt, Date(timeIntervalSinceReferenceDate: 100))
XCTAssertEqual(item.descriptionModifiedAt, Date(timeIntervalSinceReferenceDate: 100))
```

- `testV1V2V3ClassificationUnchanged` — assert `classify` still returns
  `.migratable(from: 1/2/3, …)` for the existing legacy literals after the new
  keys exist (a lightweight guard; reuse the existing v1/v3 payload shapes).

#### 7. Store tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

Using the injectable `Clock` (`ChecklistStoreTests.swift:39`), `textEditDelay: nil`:

- `testTitleEditStampsTitleClockAndLeavesDescriptionClock` — `addItem` then
  `updateItem(title:)`; assert `titleRevision == revision` and
  `titleModifiedAt == clock.now`, `descriptionRevision`/`descriptionModifiedAt`
  still equal the add-time clock.
- `testDescriptionEditStampsDescriptionClockAndLeavesTitleClock` — the mirror.
- `testCreateAddAndDuplicateSeedEveryFieldClock` — a created/added item has all
  four clocks equal to its `revision`/`modifiedAt`; a duplicated item's clocks
  are all the duplicate's `now()`/`1`.
- `testV1MigrationSeedsFieldClocks` — extend `testLegacyPayloadIsMigratedAndSavable`'s
  assertions: a migrated item's `titleRevision == descriptionRevision ==
  revision` and matching `*ModifiedAt`.
- `testTombstoneRevisionIsRemovedRevisionPlusOne` — after `removeItems`, the
  appended tombstone's `revision == removed.revision + 1` (guard the invariant
  against the new clock fields).

#### 8. Sync-service test
**File**: `CheckStitchTests/ChecklistSyncServiceTests.swift`
**Action**: modify

Add `concurrentTitleAndDescriptionEditsBothSurviveReconcile`. Preload the store
from an encoded local envelope (local device edited `title`, local side's
pre-upgrade fields absent), set `sync.stored` to an encoded remote envelope
(device B edited `description`), reconcile, and assert both values survive in
the store and in the pushed bytes:

```swift
let localItem = ChecklistItem(id: itemID, title: "A title", description: "", revision: 2,
    modifiedAt: Date(timeIntervalSince1970: 20),
    titleRevision: 2, titleModifiedAt: Date(timeIntervalSince1970: 20))
let local = ChecklistEnvelope(deviceID: "device-a", checklists: [
    Checklist(id: checklistID, name: "Groceries", items: [localItem],
              modifiedAt: Date(timeIntervalSince1970: 10), revision: 1)])
suite.defaults.set(try ChecklistCodec.encode(local), forKey: "checklists.v1")
let store = makeStore(defaults: suite.defaults)
let remoteItem = ChecklistItem(id: itemID, title: "Milk", description: "2 litres", revision: 3,
    modifiedAt: Date(timeIntervalSince1970: 30),
    descriptionRevision: 3, descriptionModifiedAt: Date(timeIntervalSince1970: 30))
let sync = InMemoryChecklistSync(stored: envelopeData(device: "device-b", checklists: [
    Checklist(id: checklistID, name: "Groceries", items: [remoteItem],
              modifiedAt: Date(timeIntervalSince1970: 10), revision: 1)]))
let service = makeService(sync: sync, store: store)
let outcome = await service.reconcile()
#expect(outcome == .synced)
#expect(store.checklists.first?.items.first?.title == "A title")
#expect(store.checklists.first?.items.first?.description == "2 litres")
let pushed = try #require(sync.stored)
#expect(ChecklistCodec.decode(pushed).first?.items.first?.title == "A title")
#expect(ChecklistCodec.decode(pushed).first?.items.first?.description == "2 litres")
```

### Verification

#### Automated
- [x] `make test-unit` passes (all four touched suites green)
- [ ] `./scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Two simulators (or a phone + simulator) signed into the same iCloud
      account: baseline the item on both, edit only the title on device A and
      only the description on device B, force a sync, and confirm each device
      ends with both edits.

---

## Phase 2: Concurrent relative-date and text edits both survive

Extend the same per-axis merge to `relativeDate`, so a date change on one
device and a text edit on another both survive, and re-committing an unchanged
date still stamps nothing.

### Changes

#### 1. Relative-date clock on `ChecklistItem`
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add `relativeDateRevision`/`relativeDateModifiedAt` exactly like Phase 1's pair:
stored properties, `CodingKeys` entries, `init` params (`relativeDateRevision:
Int? = nil, relativeDateModifiedAt: Date? = nil`) seeding `?? revision` /
`?? modifiedAt`, decode seeding, and unconditional encode.

```swift
self.relativeDateRevision = relativeDateRevision ?? revision
self.relativeDateModifiedAt = relativeDateModifiedAt ?? modifiedAt
```

`migrated(at:)`: add to the item map —

```swift
upgraded.relativeDateRevision = upgraded.revision
upgraded.relativeDateModifiedAt = date
```

#### 2. Relative-date resolution in `mergedItems`
**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: modify

Third independent block after `description`:

```swift
if fieldWins(revision: remoteItem.relativeDateRevision, date: remoteItem.relativeDateModifiedAt, device: remoteDevice,
             overRevision: localItem.relativeDateRevision, overDate: localItem.relativeDateModifiedAt, overDevice: localDevice) {
    merged.relativeDate = remoteItem.relativeDate
    merged.relativeDateRevision = remoteItem.relativeDateRevision
    merged.relativeDateModifiedAt = remoteItem.relativeDateModifiedAt
}
```

#### 3. Relative-date stamping in the store
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

Keep the existing unchanged-value guard (`ChecklistStore.swift:256`); when the
value does change, stamp the coarse clock and the relative-date clock together
(single `now()` sample), exactly as the text mutators do:

```swift
guard checklists[checklistIndex].items[itemIndex].relativeDate != relativeDate else { return }
let revisedAt = now()
checklists[checklistIndex].items[itemIndex].relativeDate = relativeDate
checklists[checklistIndex].items[itemIndex].revision += 1
checklists[checklistIndex].items[itemIndex].modifiedAt = revisedAt
checklists[checklistIndex].items[itemIndex].relativeDateRevision = checklists[checklistIndex].items[itemIndex].revision
checklists[checklistIndex].items[itemIndex].relativeDateModifiedAt = revisedAt
scheduleSave()
```

`create`/`duplicate`/`addItem` again need no code change (init seeds the third
clock; `duplicate` copies the value and seeds a fresh clock).

#### 4. Merge tests
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

Extend the `item(...)` fixture with `relativeDateRevision`/`relativeDateModifiedAt`
(default `nil`) and add:

- `relativeDateAndTitleEditsOnDifferentDevicesBothSurvive` — device A changes
  the relative date, device B the title; assert both survive.
- `relativeDateAndTitleEditsOnDifferentDevicesBothSurviveReversed` — swapped
  argument order; assert equal `checklists`.

#### 5. Codec tests
**File**: `CheckStitchTests/ChecklistCodecTests.swift`
**Action**: modify

- Extend `testFieldClocksSurviveEnvelopeRoundTrip` to cover all six keys.
- Extend `testItemWithoutFieldClocksSeedsFromCoarseClock` to assert
  `relativeDateRevision == revision` and `relativeDateModifiedAt == modifiedAt`.

#### 6. Store tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

- `testUnchangedRelativeDateIsANoOpForEveryClock` — set the same value twice;
  all six clocks and the coarse clock are unchanged after the second call.
- `testChangedRelativeDateStampsRelativeDateClockOnly` — change the value;
  `relativeDateRevision`/`relativeDateModifiedAt` match the coarse clock, while
  title/description clocks are untouched.
- `testMoveItemsLeavesEveryFieldClockUntouched` — extend
  `testMovePreservesItemIdentity`'s assertions to include the six clocks.

### Verification

#### Automated
- [x] `make test-unit` passes (all six clocks covered by codec + merge + store)
- [ ] `./scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Two devices: set a relative date on one and edit the title on the other;
      after sync both edits are present, and opening/re-committing the date
      picker without changing the value causes no further write.

---

## Phase 3: Hardening — mixed-version fixtures, churn, watch transport

Close the design's flagged risks: legacy fixtures must not spuriously reassign
fields, clock-only differences must not cause a push-back loop, and per-field
clocks must survive the watch context transport (`deviceID: ""`).

### Changes

No new wire keys and no implementation change is planned; only add tests, and
touch implementation only if a test exposes a defect (see "If a test fails"
below).

#### 1. Mixed-fixture merge test
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

`legacySeededClocksResolveOneWinningField` — a legacy item constructed with the
plain init (its field clocks seed from the coarse clock) merges with a
post-upgrade item whose description was edited and whose title clock is older:

```swift
let legacy = item(id: itemID, title: "Milk", description: "old note",
                  revision: 5, modifiedAt: Date(timeIntervalSince1970: 50))   // clocks seeded 5/t50
let upgraded = item(id: itemID, title: "Milk (typo)", description: "new note",
                    revision: 4, modifiedAt: Date(timeIntervalSince1970: 40),
                    titleRevision: 3, titleModifiedAt: Date(timeIntervalSince1970: 30),
                    descriptionRevision: 6, descriptionModifiedAt: Date(timeIntervalSince1970: 60))
```

After merge: `title == "Milk"` (legacy's seeded 5/t50 clock wins over 3/t30),
`description == "new note"` (6/t60 wins), and merging the result with the
original remote again is a `contentEquals` no-op.

#### 2. Push-churn / idempotence test
**File**: `CheckStitchTests/ChecklistSyncServiceTests.swift`
**Action**: modify

`fieldClocksDoNotCausePushChurn` — preload the store from an encoded local
envelope (written with `forKey: "checklists.v1"`, the store's default key) with
explicit field clocks; set `sync.stored` to a raw-JSON v4 remote item **without**
the field keys but with the same `revision`/`modifiedAt`; after
reconcile assert `sync.written.isEmpty` and a second reconcile writes nothing
too (the decoded-remote seeded clocks equal the local clocks, so
`contentEquals` stays true). Remote JSON shape:

```swift
let remote = Data(#"{"version":4,"deviceID":"device-b","tombstones":[],"checklists":[{"id":"\#(checklistID.uuidString)","name":"Groceries","modifiedAt":100,"revision":1,"items":[{"id":"\#(itemID.uuidString)","title":"Milk","description":"2 litres","revision":3,"modifiedAt":100}]}]}"#.utf8)
```

(JSONEncoder's default `deferredToDate` strategy encodes `Date` as seconds since
the 2001 reference date, so `100` decodes to `Date(timeIntervalSinceReferenceDate: 100)`.)
Local clocks must use the same values.

#### 3. Watch context transport
**File**: `CheckStitchTests/WatchChecklistStoreTests.swift`
**Action**: modify

`fieldClocksSurviveTheWatchContext` — deliver a `.context` envelope encoded with
`deviceID: ""` whose item carries explicit per-field clocks; assert the stored
item's six clocks match (mirrors `contextReplacesTheChecklistList`).

#### 4. Coordinator tie-break with an empty device id
**File**: `CheckStitchTests/ChecklistSyncCoordinatorTests.swift`
**Action**: modify

`perFieldClocksSurviveTheCoordinatorPush` — `start()` a coordinator whose
snapshot items carry explicit field clocks; decode `transport.sentContexts[0]`
and assert all six clocks round-trip.

#### 5. Empty-device deterministic merge
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

`emptyDeviceIDsResolvePerFieldDeterministically` — both envelopes use
`deviceID: ""` and equal field clocks; merge in both argument orders and assert
`checklists` are equal and no field changes (no win without a device id, matching
`wins`' `guard let device` behavior).

### If a test exposes a defect

- **Push churn loop** (Phase 3.2): the only permitted implementation tweak is
  `ChecklistMerge.mergedItems` / `contentEquals` clock handling — do **not**
  change `ChecklistItem` equality or the wire format. Re-check that the field
  clocks copied on a win are exactly the winner's.
- **Watch drops clocks** (Phase 3.3/3.4): the transport encodes/decodes the
  whole `ChecklistEnvelope` via `ChecklistCodec`, so a failure means a
  `CodingKeys`/encode omission — fix the codec, not the watch code.
- Anything else: stop and report; do not redesign the merge.

### Verification

#### Automated
- [ ] `make test-unit` passes (merge + service + coordinator + watch suites)
- [ ] `./scripts/test.sh` prints `gate: ok` (includes `make watch-build`)

#### Manual
- [ ] Install a fresh old-version build and a new build on two devices sharing
      the same App Group: create an item on the old build, edit it on the new
      build, sync both ways, and confirm the untouched field is not reassigned.
- [ ] Watch: edit an item on the phone, confirm the watch context still shows
      title/description/date and that a date change on the phone reaches it.

---

## Testing checkpoints

- [ ] After Phase 1: `ChecklistMergeTests`, `ChecklistCodecTests`,
      `ChecklistStoreTests`, `ChecklistSyncServiceTests` green under
      `make test-unit` — do not start Phase 2 otherwise.
- [ ] After Phase 2: all six clocks covered in codec + merge + store suites —
      the wire contract is frozen.
- [ ] After Phase 3: full gate `./scripts/test.sh` prints `gate: ok`, including
      the watch compile leg.

## Files touched (completeness check against `structure.md`)

- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` (Phase 1, 2)
- `CheckStitch/ChecklistMerge.swift` (Phase 1, 2)
- `CheckStitch/ChecklistStore.swift` (Phase 1, 2)
- `CheckStitchTests/ChecklistMergeTests.swift` (Phase 1, 2, 3)
- `CheckStitchTests/ChecklistCodecTests.swift` (Phase 1, 2)
- `CheckStitchTests/ChecklistStoreTests.swift` (Phase 1, 2)
- `CheckStitchTests/ChecklistSyncServiceTests.swift` (Phase 1, 3)
- `CheckStitchTests/ChecklistSyncCoordinatorTests.swift` (Phase 3)
- `CheckStitchTests/WatchChecklistStoreTests.swift` (Phase 3)

No new source files → no `.pbxproj` edit needed
(`PBXFileSystemSynchronizedRootGroup`). No migration/schema-version test
assertions to update: `currentVersion` stays `4` and `classify` is untouched.