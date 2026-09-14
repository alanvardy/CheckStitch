# Implementation Plan

## Overview

Make ordering first-class mergeable state on `Checklist` (`itemOrder: [UUID]` +
`orderRevision`/`orderModifiedAt`), bump the codec to v3 with a one-way v2→v3
migration, reconcile order in `ChecklistMerge` using the existing `wins`
tiebreak, expose `ChecklistStore.moveItems(checklistID:from:to:)` (silent no-op
on bad input), and wire it to `.onMove` + an edit affordance in
`ChecklistDetailView`. Each layer is fully tested before the next:
model/codec → merge → store → UI.

Ticket VAR-995. All work on this branch; no child tickets.

> **Deviation from `structure.md` (recorded):** `EditButton` is
> `@available(macOS, unavailable)` (verified in the macOS SDK `.swiftinterface`),
> and `make build-mac` compiles the whole app target — an unguarded
> `EditButton()` breaks the gate. The plan wraps it in `#if os(iOS)`. On macOS
> reordering works without edit mode, so nothing is lost. This is the only
> deviation; phase order and file set are unchanged.

---

## Phase 1: Model & Codec — `itemOrder` and the v3 migration

### Changes

#### 1. `Checklist` stored properties, init, coding, migration, normalizer
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add three stored properties and extend the public initializer. `itemOrder` is
`nil`-defaulted and derived from `items` so every existing call site keeps its
meaning; an **explicit** `itemOrder` is kept verbatim so tests can construct a
drifted value for the normalizer's sad path.

```swift
public init(
    id: UUID = UUID(), name: String = "New checklist", items: [ChecklistItem] = [],
    modifiedAt: Date = .distantPast, revision: Int = 0,
    itemOrder: [UUID]? = nil, orderRevision: Int = 0, orderModifiedAt: Date = .distantPast
) {
    self.id = id
    self.name = name
    self.items = items
    self.modifiedAt = modifiedAt
    self.revision = revision
    // Canonical order defaults to the array's own order; an explicit value is
    // honoured so drift can be constructed/observed by tests.
    self.itemOrder = itemOrder ?? items.map(\.id)
    self.orderRevision = orderRevision
    self.orderModifiedAt = orderModifiedAt
}

public let id: UUID
public var name: String
public var items: [ChecklistItem]
public var modifiedAt: Date
public var revision: Int
/// Canonical item ordering as a list of item ids. Kept in lockstep with
/// `items` (see `normalizedOrder()`); stamped independently of item
/// `revision`/`modifiedAt` so a reorder is never mistaken for an item edit.
public var itemOrder: [UUID]
public var orderRevision: Int
public var orderModifiedAt: Date
```

Coding: add the three keys, decode with defaults (deriving `itemOrder` from the
decoded `items` when absent), then self-heal through `normalizedOrder()`.

```swift
private enum CodingKeys: String, CodingKey {
    case id, name, items, modifiedAt, revision, itemOrder, orderRevision, orderModifiedAt
}

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    items = try container.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
    modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    itemOrder = try container.decodeIfPresent([UUID].self, forKey: .itemOrder) ?? items.map(\.id)
    orderRevision = try container.decodeIfPresent(Int.self, forKey: .orderRevision) ?? 0
    orderModifiedAt = try container.decodeIfPresent(Date.self, forKey: .orderModifiedAt) ?? .distantPast
    // Decode-time self-heal: a payload whose `itemOrder` disagrees with `items`
    // (or omits an id) is canonicalised rather than trusted.
    self = normalizedOrder()
}

public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(items, forKey: .items)
    try container.encode(modifiedAt, forKey: .modifiedAt)
    try container.encode(revision, forKey: .revision)
    try container.encode(itemOrder, forKey: .itemOrder)
    try container.encode(orderRevision, forKey: .orderRevision)
    try container.encode(orderModifiedAt, forKey: .orderModifiedAt)
}
```

`migrated(at:)` (pre-order → v3) gains order seeding. Capture the record's own
values **before** the existing stamping so the migrated order timestamp does not
become `now()`:

```swift
public func migrated(at date: Date) -> Checklist {
    var copy = self
    let priorModifiedAt = modifiedAt
    copy.modifiedAt = date
    copy.revision = max(revision, 1)
    // Pre-v3 payloads carry no ordering; seed it from the record's own
    // revision/date so migration grants no spurious ordering win.
    copy.orderRevision = max(revision, 1)
    copy.orderModifiedAt = priorModifiedAt
    if copy.itemOrder.isEmpty {
        copy.itemOrder = copy.items.map(\.id)
    }
    copy.items = copy.items.map { item in
        var upgraded = item
        upgraded.modifiedAt = date
        upgraded.revision = max(upgraded.revision, 1)
        return upgraded
    }
    return copy
}
```

Add the normalizer to the existing `extension Checklist`:

```swift
extension Checklist {
    /// Canonicalises `items` to `itemOrder` and appends any item id missing
    /// from it, so the encoded array order and the explicit order never
    /// diverge. Idempotent; used on decode, after merge, and after any
    /// mutation that touches `items`.
    func normalizedOrder() -> Checklist {
        var copy = self
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var order: [UUID] = []
        var seen = Set<UUID>()
        for id in itemOrder where byID[id] != nil && seen.insert(id).inserted {
            order.append(id)
        }
        for item in items where seen.insert(item.id).inserted {
            order.append(item.id)
        }
        copy.itemOrder = order
        copy.items = order.compactMap { byID[$0] }
        return copy
    }
}
```

> If `self = normalizedOrder()` is rejected by the compiler in
> `init(from:)`, fall back to assigning a freshly built value:
> `self = Checklist(id: id, name: name, items: items, modifiedAt: modifiedAt,
> revision: revision, itemOrder: itemOrder, orderRevision: orderRevision,
> orderModifiedAt: orderModifiedAt).normalizedOrder()`.

#### 2. Codec version 3 and v2→v3 migration
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify (same file — `ChecklistCodec` lives below `Checklist`)

```swift
public static let currentVersion = 3
```

```swift
        switch probe.version {
        case currentVersion:
            return .loaded(try JSONDecoder().decode(ChecklistEnvelope.self, from: data))
        case 1, 2:
            let legacy = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
            return .migratable(from: probe.version, checklists: legacy.checklists)
        default:
            logger.error("Unsupported checklist payload version \(probe.version, privacy: .public); treating as empty")
            return .unsupportedVersion
        }
```

The `.migratable(_, let checklists)` consumers already exist and need no change:
`ChecklistStore.init` (`legacy.map { $0.migrated(at: now()) }`) and
`ChecklistSyncService.reconcileNow` (`checklists.map { $0.migrated(at: .distantPast) }`).

#### 3. Tests
**Files**: `CheckStitchTests/ChecklistCodecTests.swift`,
`CheckStitchTests/ChecklistItemTests.swift`,
`CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

`ChecklistCodecTests` (XCTest):
- `testEnvelopeRoundTrip` — unchanged; add an assertion that the encoded JSON
  contains `"itemOrder"` and the decoded `orderRevision` survives.
- `testLegacyV1PayloadIsClassifiedMigratable` — unchanged (still
  `.migratable(from: 1, ...)`).
- Add `testV2PayloadIsClassifiedMigratable`: a real v2 payload (version 2, with
  `deviceID`/`tombstones`, checklist with `modifiedAt`/`revision`, item with
  `modifiedAt`/`revision`, **no** order keys) → `.migratable(from: 2,
  checklists:)`.
- Add `testV3RoundTripPreservesOrder`: build a `Checklist` with an explicit
  `itemOrder` different from `items` order, encode, classify as `.loaded`,
  assert `decoded.itemOrder == normalized items.map(\.id)` and array order matches.
- Existing `testUnknownVersionDecodesAsEmpty` (version 99) and
  `testClassifyDistinguishesUnsupportedFromUnreadable` stay green (>v3 →
  `.unsupportedVersion`).

`ChecklistItemTests` (Swift Testing) — add:
- `checklistDecodeDefaultsToDerivedOrder` — decode a JSON checklist with
  `items` but no order keys; assert `itemOrder == items.map(\.id)`,
  `orderRevision == 0`, `orderModifiedAt == .distantPast`.
- `normalizedOrderRepairsDrift` (happy path) — construct
  `Checklist(items: [a, b], itemOrder: [b])`; assert `normalizedOrder()`
  returns `itemOrder == [b, a]` and `items.map(\.id) == [b, a]`.
- `normalizedOrderAppendsMissingItem` (sad path) — construct
  `Checklist(items: [a, b, c], itemOrder: [a, c])`; assert the result is
  `[a, c, b]` (missing `b` appended) and never drops an item.

`ChecklistStoreTests` (XCTest) — **update the version assertion** (rule: schema
bump updates schema-version assertions):
- Rename `testNewPayloadIsVersionTwo` → `testNewPayloadIsVersionThree`, assert
  `stored.version == 3`.
- Add `testV2PayloadIsMigratedAndSavable`: seed a v2 payload, construct the
  store, assert it loads with `orderRevision >= 1` and `itemOrder ==
  items.map(\.id)`, then `store.create()` and reload to prove it is savable.
- `testLegacyPayloadIsMigratedAndSavable` (v1) stays and should additionally
  assert `orderRevision == 1`.

### Verification
#### Automated
- [x] `make test-unit` passes (all suites; `ChecklistCodecTests`,
  `ChecklistItemTests`, `ChecklistStoreTests` green).
- [x] `rg -n 'currentVersion = 3' CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
  confirms the bump.
- [x] `WatchChecklistStoreTests`, `ChecklistSyncCoordinatorTests`,
  `ChecklistSyncServiceTests` remain green (they encode with
  `ChecklistCodec.currentVersion`, so they follow the bump).

#### Manual
- [ ] None for this phase (pure model/codec).

---

## Phase 2: Merge — order reconciliation in `ChecklistMerge`

### Changes

#### 1. Order conflict + reconciliation
**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: modify

`mergedChecklists` picks the ordering winner with the existing `wins` shape and
reconciles the merged item list to a deterministic order. `mergedItems` keeps
its current membership semantics (local-first, remote-only appended); the
caller reorders its output.

```swift
private static func mergedChecklists(
    _ local: [Checklist], _ remote: [Checklist],
    localDevice: String, remoteDevice: String
) -> [Checklist] {
    var result = local
    var indexByID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) })
    for remoteChecklist in remote {
        guard let index = indexByID[remoteChecklist.id] else {
            indexByID[remoteChecklist.id] = result.count
            result.append(remoteChecklist.normalizedOrder())
            continue
        }
        let localChecklist = result[index]
        var merged = localChecklist
        if wins(revision: remoteChecklist.revision, date: remoteChecklist.modifiedAt,
                device: remoteDevice,
                overRevision: localChecklist.revision, overDate: localChecklist.modifiedAt,
                overDevice: localDevice) {
            merged.name = remoteChecklist.name
            merged.revision = remoteChecklist.revision
            merged.modifiedAt = remoteChecklist.modifiedAt
        }

        let mergedItems = mergedItems(
            localChecklist.items, remoteChecklist.items,
            localDevice: localDevice, remoteDevice: remoteDevice
        )
        let remoteWinsOrder = wins(
            revision: remoteChecklist.orderRevision, date: remoteChecklist.orderModifiedAt,
            device: remoteDevice,
            overRevision: localChecklist.orderRevision, overDate: localChecklist.orderModifiedAt,
            overDevice: localDevice
        )
        let winnerOrder = remoteWinsOrder ? remoteChecklist.itemOrder : localChecklist.itemOrder
        let order = reconciledOrder(
            winnerOrder: winnerOrder,
            mergedItems: mergedItems,
            fallback: localChecklist.itemOrder
        )
        merged.items = reorder(mergedItems, to: order)
        merged.itemOrder = order
        if remoteWinsOrder {
            merged.orderRevision = remoteChecklist.orderRevision
            merged.orderModifiedAt = remoteChecklist.orderModifiedAt
        }
        result[index] = merged
    }
    return result
}
```

New helpers (placed next to `mergedItems`):

```swift
/// The merged item id order: winner ids that survive keep winner order; ids
/// that survive only in the merged list are appended. Deterministic and
/// symmetric for normalised inputs (each side's `itemOrder` covers its own
/// items, so the appended sequence is the loser's relative order either way).
private static func reconciledOrder(
    winnerOrder: [UUID], mergedItems: [ChecklistItem], fallback: [UUID]
) -> [UUID] {
    let surviving = Set(mergedItems.map(\.id))
    var order: [UUID] = []
    var seen = Set<UUID>()
    for id in winnerOrder where surviving.contains(id) && seen.insert(id).inserted {
        order.append(id)
    }
    for id in fallback + mergedItems.map(\.id)
    where surviving.contains(id) && seen.insert(id).inserted {
        order.append(id)
    }
    return order
}

/// Rebuilds `items` in the reconciled id order. `order` is exactly the set of
/// merged item ids, so nothing is dropped.
private static func reorder(_ items: [ChecklistItem], to order: [UUID]) -> [ChecklistItem] {
    let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    return order.compactMap { byID[$0] }
}
```

`mergedItems` itself is unchanged. `reconciledOrder` only touches ids in
`mergedItems`, so tombstoned ids (already removed by `merge`) never reappear.

#### 2. Tests
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

Extend the fixture builder to pass ordering through (keeps existing call sites
valid — all labelled):

```swift
@MainActor
func checklist(
    id: UUID, name: String, revision: Int, modifiedAt: Date = .distantPast,
    itemOrder: [UUID]? = nil, orderRevision: Int = 0, orderModifiedAt: Date = .distantPast,
    items: [ChecklistItem] = []
) -> Checklist {
    Checklist(id: id, name: name, items: items, modifiedAt: modifiedAt, revision: revision,
              itemOrder: itemOrder, orderRevision: orderRevision, orderModifiedAt: orderModifiedAt)
}
```

Add tests (Swift Testing, `@MainActor struct ChecklistMergeTests`):
- `orderWinnerIsHigherOrderRevision` — same items, local order `[a,b]` rev 1,
  remote order `[b,a]` rev 2; merged `itemOrder == [b,a]` in **both** argument
  orders.
- `orderTieBreaksByTimestampThenDevice` — equal `orderRevision`, newer
  `orderModifiedAt` wins; equal both → lexicographically smaller device wins,
  asserted in both argument orders.
- `remoteOnlyItemIsAppendedInWinnerOrder` — remote has an extra item id; the
  order winner's ids come first and the remote-only id is appended.
- `remoteOnlyItemIsAppendedWhenOrderWinnerIsLocal` — same, with the local
  ordering winner (guards the symmetric-append path).
- `tombstonedItemIsExcludedFromMergedOrder` — item tombstone removes the id
  from the merged `items` **and** `itemOrder`.
- `orderReconciliationIsSymmetric` — a richer scenario (order conflict +
  remote-only item + shared item) where
  `ChecklistMerge.merge(local: a, remote: b).checklists ==
  ChecklistMerge.merge(local: b, remote: a).checklists` (compare `checklists`,
  since the merged `deviceID` is always the local one).
- `orderReconciliationIsIdempotent` — `let once = merge(local, remote)`;
  `merge(local: once, remote: once).checklists == once.checklists` and
  `merge(local: once, remote: remote).checklists == once.checklists`.
- Existing `identicalEnvelopesAreANoOp` must stay green (it is the `apply`
  guard's regression test).

### Verification
#### Automated
- [x] `make test-unit` passes, including the new symmetry/idempotence cases.
- [x] `rg -n 'reconciledOrder|remoteWinsOrder' CheckStitch/ChecklistMerge.swift`
  confirms the wiring.

#### Manual
- [ ] None (pure function).

---

## Phase 3: Store — `moveItems` and the order invariant

### Changes

#### 1. `moveItems` + keep `items`/`itemOrder` in lockstep
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

Add a generic move helper mirroring SwiftUI's `move(fromOffsets:toOffset:)`
arithmetic (destination is an insertion index in the **pre-move** array). The
helper returns `nil` for bad input, which the public method turns into a silent
no-op (matching `removeItems`' guard and `addItem`/`updateItem`'s unknown-id
behaviour).

```swift
/// Applies SwiftUI's `move(fromOffsets:toOffset:)` index arithmetic: removes
/// the offsets (descending) and re-inserts them at the destination adjusted by
/// the number of removed elements that sat before it. Returns `nil` for any
/// out-of-range input so callers can no-op.
private static func moved<T>(_ array: [T], from offsets: IndexSet, to destination: Int) -> [T]? {
    guard !offsets.isEmpty else { return nil }
    guard offsets.allSatisfy({ array.indices.contains($0) }) else { return nil }
    guard destination >= 0 && destination <= array.count else { return nil }
    let moving = offsets.sorted().map { array[$0] }
    var result = array
    for offset in offsets.sorted(by: >) { result.remove(at: offset) }
    let insertion = destination - offsets.filter { $0 < destination }.count
    result.insert(contentsOf: moving, at: insertion)
    return result
}

/// Reorders a checklist's items. A structural edit, so it stamps the ordering
/// state and persists immediately — item `id`/`title`/`modifiedAt`/`revision`
/// are untouched, so a pure reorder is never mistaken for an item edit.
/// Unknown checklist ids and out-of-range offsets/destinations are silent
/// no-ops.
func moveItems(checklistID: UUID, from offsets: IndexSet, to destination: Int) {
    guard let index = checklists.firstIndex(where: { $0.id == checklistID }) else { return }
    guard let items = Self.moved(checklists[index].items, from: offsets, to: destination) else { return }
    checklists[index].items = items
    // Same order, kept in lockstep with the canonical list.
    checklists[index].itemOrder = items.map(\.id)
    checklists[index].orderRevision += 1
    checklists[index].orderModifiedAt = now()
    save()
}
```

`addItem(to:)` must append the new id so the invariant holds:

```swift
func addItem(to id: UUID) {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
    let item = ChecklistItem(title: "New item", modifiedAt: now(), revision: 1)
    checklists[index].items.append(item)
    checklists[index].itemOrder.append(item.id)
    save()
}
```

`removeItems(from:at:)` must drop the deleted ids:

```swift
for offset in offsets.sorted(by: >) {
    guard checklists[index].items.indices.contains(offset) else { continue }
    let removed = checklists[index].items.remove(at: offset)
    checklists[index].itemOrder.removeAll { $0 == removed.id }
    tombstones.append(ChecklistTombstone(
        checklistID: id, itemID: removed.id, deletedAt: now(), revision: removed.revision + 1))
}
```

`apply(remote:)` self-heals after merge (no new stamps):

```swift
var merged = ChecklistMerge.merge(local: envelope, remote: remote)
merged.checklists = merged.checklists.map { $0.normalizedOrder() }
guard merged != envelope else { return false }   // idempotent
let visibleChanged = merged.checklists != checklists
```

(Everything else in `apply` is unchanged.)

No change to `updateItem`, `rename`, `create`, `delete`, `scheduleSave`,
`flushPendingSave`, or `save`.

#### 2. Tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

Add a small helper for constructing a store with a known set of titled items,
then the cases below (XCTest, `@MainActor`, `textEditDelay: nil`, isolated
defaults + `defer` cleanup, reload via a second store on the same defaults):

- `testMoveReordersItemsWithinList` — 3 items `[A,B,C]`, `moveItems(from:
  IndexSet(integer: 0), to: 2)` → titles `[B,A,C]`; `itemOrder` matches
  `items.map(\.id)`.
- `testMoveToEnd` — `moveItems(from: IndexSet(integer: 0), to: 3)` on `[A,B,C]`
  → `[B,C,A]`.
- `testMoveOutOfRangeIsNoOp` — `IndexSet(integer: 9)`, `to: -1`, and `to: 99`
  each leave `items`, `itemOrder`, `orderRevision`, `orderModifiedAt` and the
  persisted payload unchanged.
- `testMoveUnknownChecklistIsNoOp` — unknown id leaves all checklists and the
  persisted payload unchanged (assert raw `defaults.data(forKey: key)`).
- `testMovePreservesItemIdentity` — snapshot each item's
  `id`/`title`/`modifiedAt`/`revision` and the checklist's `name`/`revision`/
  `modifiedAt` before the move; assert byte-for-byte equality after, while
  `orderRevision` increments and `orderModifiedAt` advances (use the `Clock`).
- `testMoveStampsOrderNotChecklist` — `orderRevision` goes 0 → 1,
  `orderModifiedAt == clock.now`, checklist `revision`/`modifiedAt` unchanged.
- `testMovePersistsAcrossReload` — move, reload, assert order + `orderRevision`.
- `testAddItemAppendsToItemOrder` — after `addItem`, `itemOrder.last ==
  items.last?.id`.
- `testRemoveItemsDropsFromItemOrder` — after `removeItems`, no deleted id
  remains in `itemOrder` and `itemOrder == items.map(\.id)`.
- `testApplyKeepsItemsAndItemOrderInLockstep` — apply a remote envelope whose
  checklist carries an order conflict + a remote-only item; assert
  `itemOrder == items.map(\.id)` and `apply` returns `true` on first call,
  `false` on the identical second call (idempotence guard intact).
- Existing `testAddAndRemoveItemPersists`, `testApplyIsIdempotent`,
  `testApplyMergesRemoteChecklist`, the debounce/stamp suites stay green.

### Verification
#### Automated
- [ ] `make test-unit` passes.
- [ ] `bash scripts/test.sh` prints `gate: ok` (full simulator + mac + watch +
  shell-test + shellcheck gate) **before** touching the UI layer.
- [ ] `rg -n 'func moveItems' CheckStitch/ChecklistStore.swift` confirms the
  public API name matches the ticket.

#### Manual
- [ ] None required; the drag affordance lands in Phase 4.

---

## Phase 4: UI — `.onMove` + edit affordance

### Changes

#### 1. Wire the drag gesture
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Add `.onMove` alongside the existing `.onDelete` on the items `ForEach` (the
`ForEach` keeps relying on `ChecklistItem: Identifiable`; add `id: \.id`
explicitly only if the render/behaviour check shows it is required):

```swift
Section("Items") {
    ForEach(checklist.items) { item in
        TextField("Item", text: titleBinding(checklistID: checklistID, itemID: item.id))
    }
    .onDelete { offsets in
        store.removeItems(from: checklistID, at: offsets)
    }
    .onMove { offsets, destination in
        store.moveItems(checklistID: checklistID, from: offsets, to: destination)
    }
}
```

Add the edit-mode toggle to the existing toolbar. **`EditButton` is
`@available(macOS, unavailable)`**, so it is iOS-only; macOS reorders by drag
without edit mode, and `make build-mac` still compiles:

```swift
.toolbar {
    #if os(iOS)
    ToolbarItem(placement: .topBarLeading) { EditButton() }
    #endif
    ToolbarItem(placement: .confirmationAction) {
        Button("Done") { commitRename() }
            .fixedSize()
    }
}
```

No new view state, no direct mutation: everything still routes through
`ChecklistStore`.

#### 2. Tests
**File**: `CheckStitchTests/ViewRenderTests.swift`
**Action**: modify

Add a render smoke for the detail screen — it proves the new modifier chain
compiles and the body evaluates against a real store:

```swift
@Test
func detailViewRendersForEmptyAndNonEmptyChecklists() {
    let defaults = makeIsolatedDefaults()
    let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
    let empty = store.create(name: "Empty")
    let filled = store.create(name: "Filled")
    store.addItem(to: filled.id)

    let emptyView = ChecklistDetailView(checklistID: empty.id).environment(store)
    let filledView = ChecklistDetailView(checklistID: filled.id).environment(store)
    #expect(String(describing: emptyView.body).isEmpty == false)
    #expect(String(describing: filledView.body).isEmpty == false)
}
```

The UI smoke (`CheckStitchUITests/CheckStitchUITests.swift`,
`testLaunchAndAccessibilitySmoke`) is unchanged and must stay green.

### Verification
#### Automated
- [ ] `make test-unit` passes (includes the new render test).
- [ ] `bash scripts/test.sh` prints `gate: ok` — this covers `make build`
  (simulator), `make test`, `make build-mac`, `make watch-build`,
  `scripts/tests/run.sh`, and `shellcheck`.
- [ ] `make test-ui` is green on this worktree's simulator (the smoke case).

#### Manual
- [ ] `make run`: create a checklist, add ≥3 items, tap **Edit**, drag a row up
  and down, confirm the order changes and the item text is unchanged.
- [ ] Relaunch the app (`make run` again): the reordered order persists.
- [ ] On the macOS slice (`make build-mac-signed` + run), confirm the `Form`
  rows can be reordered by drag without an edit button, and that nothing in the
  items section regressed (delete still works, text fields still edit).
- [ ] Confirm a reorder does **not** alter any item's text or trigger an item
  edit (no reminder-affecting behaviour).

---

## Cross-cutting risks carried into implementation

- **Mixed app versions** (accepted by design Q5B): a v2 build classifies a v3
  payload `.unsupportedVersion` and refuses to save/sync. Not tested; document
  in the PR description.
- **`items`/`itemOrder` drift**: prevented by `normalizedOrder()` on decode,
  after merge, and by keeping `addItem`/`removeItems`/`moveItems` in lockstep;
  each of those paths has a test.
- **`apply` idempotence**: `reconciledOrder` is deterministic, monotonic in the
  winner, and appended ids follow the loser's relative order, so a re-merge is
  a no-op; covered by the new merge idempotence test and
  `testApplyKeepsItemsAndItemOrderInLockstep`.
- **macOS `EditButton`**: guarded by `#if os(iOS)`; `make build-mac` is the
  proof the guard is correct.
- **`self = normalizedOrder()` in `init(from:)`**: if the compiler rejects it,
  use the fallback noted in Phase 1 (build a value and assign `self`).
- **`Form`/`List` drag-handle rendering on macOS**: not unit-testable; the
  manual macOS step above is the only check.
