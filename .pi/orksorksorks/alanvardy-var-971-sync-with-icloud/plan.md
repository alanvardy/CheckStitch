# Implementation Plan

## Overview

Checklists and their items round-trip across devices through the user's iCloud
key-value store while the local `ChecklistStore` stays the offline cache and the
UI's only write path, and `ContentView` gains a pull-to-refresh that force-reconciles
sync and surfaces failures. Reminders creation is untouched.

All work lands on the main ticket (no child tickets). Stage order is fixed
(schema → seam → merge → store → coordinator → UI); `make test-unit` must be
green before each next stage.

### Refinements to `structure.md` (flagged, not silent)

1. **`ChecklistCodec.Outcome.migratable` carries the legacy checklists.**
   Structure wrote `.migratable(from: Int, deviceID: String)`, but the store needs
   the decoded v1 checklists to migrate them, and the store already knows its own
   `deviceID`. The plan uses `.migratable(from: Int, checklists: [Checklist])`.
2. **`ChecklistCodec.encode` takes the whole envelope.** Structure wrote
   `encode(_:deviceID:tombstones:)`; the store is the only encoder and already
   holds an envelope, so the plan uses a single `encode(_ envelope:) ->
   Data`. This keeps "store is the only encoder" literally true.
3. **The seam methods throw.** Structure's Stage-2 protocol has `read() -> Data?`
   / `write(_:)`, but Stage 5 requires "`read()` failure → `.unavailable`".
   Throwing matches the mirrored `ReminderCreating` seam, so
   `read() throws -> Data?` / `write(_:) throws`.
4. **`.refreshable` attaches to the existing `checklistList` `ScrollView`, not a
   SwiftUI `List`** (there is no `List` in `ContentView`; the list is a
   `ScrollView`/`LazyVStack` card). iOS 18.7 supports `.refreshable` on
   `ScrollView`.
5. **`start()` wires observers only; the initial reconcile runs from
   `syncOnLaunch()`** (structure bundled them, but `start()` is synchronous and
   `MyApp` already has a `.task` hook for the async work). Double-reconcile is
   coalesced anyway.

---

## Phase 1 — Schema v2 & migration

### Changes

#### 1. Persisted models gain sync state and legacy-tolerant decoding
**File**: `CheckStitch/Checklist.swift`
**Action**: modify

`ChecklistItem` and `Checklist` gain `modifiedAt`/`revision`. Because Swift's
synthesized `Decodable` does **not** apply stored-property defaults for missing
keys, each type needs an explicit `init(from:)` that `decodeIfPresent`s the new
fields, plus an explicit `encode(to:)` (do not rely on synthesis once
`init(from:)` is hand-written).

```swift
struct ChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var modifiedAt: Date
    var revision: Int

    init(id: UUID = UUID(), title: String, modifiedAt: Date = .distantPast, revision: Int = 0) {
        self.id = id
        self.title = title
        self.modifiedAt = modifiedAt
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey { case id, title, modifiedAt, revision }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(revision, forKey: .revision)
    }
}
```

`Checklist` mirrors this (`modifiedAt`/`revision`, keeping the existing
`init(id:name:items:)` with the two new defaulted parameters). Add the migration
helper here too:

```swift
extension Checklist {
    /// Upgrades a v1 entry: v1 carried no sync state, so stamp it rather than
    /// rejecting the payload (structure Stage 1).
    func migrated(at date: Date) -> Checklist {
        var copy = self
        copy.modifiedAt = date
        copy.revision = max(revision, 1)
        copy.items = copy.items.map { item in
            var upgraded = item
            upgraded.modifiedAt = date
            upgraded.revision = max(upgraded.revision, 1)
            return upgraded
        }
        return copy
    }
}
```

#### 2. Tombstone + v2 envelope + codec
**File**: `CheckStitch/Checklist.swift`
**Action**: modify

```swift
struct ChecklistTombstone: Codable, Hashable {
    let checklistID: UUID
    let itemID: UUID?
    var deletedAt: Date
    var revision: Int
}

struct ChecklistEnvelope: Codable, Equatable {
    var version: Int
    var deviceID: String
    var checklists: [Checklist]
    var tombstones: [ChecklistTombstone]

    init(version: Int = ChecklistCodec.currentVersion,
         deviceID: String,
         checklists: [Checklist],
         tombstones: [ChecklistTombstone] = []) { ... }

    private enum CodingKeys: String, CodingKey { case version, deviceID, checklists, tombstones }

    // v1 payloads have neither deviceID nor tombstones.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        checklists = try container.decodeIfPresent([Checklist].self, forKey: .checklists) ?? []
        tombstones = try container.decodeIfPresent([ChecklistTombstone].self, forKey: .tombstones) ?? []
    }
    func encode(to encoder: Encoder) throws { /* symmetric */ }
}

extension ChecklistEnvelope {
    /// Envelope equality ignoring the producer's device id — used to decide
    /// whether a reconciled result must be pushed back to the cloud.
    func contentEquals(_ other: ChecklistEnvelope) -> Bool {
        version == other.version && checklists == other.checklists && tombstones == other.tombstones
    }
}
```

Update the codec:

```swift
enum ChecklistCodec {
    static let currentVersion = 2

    enum Outcome: Equatable {
        case loaded(ChecklistEnvelope)
        /// A known older version that can be upgraded in place.
        case migratable(from: Int, checklists: [Checklist])
        /// Written by a future version whose shape is unknown.
        case unsupportedVersion
        /// Garbage that is safe to replace.
        case unreadable
    }

    static func encode(_ envelope: ChecklistEnvelope) throws -> Data {
        try JSONEncoder().encode(envelope)
    }

    /// Classifies a payload — never a crash, never a partial decode. Probes the
    /// version before decoding the rest so a future version is never mis-read.
    static func classify(_ data: Data) -> Outcome {
        do {
            let probe = try JSONDecoder().decode(VersionProbe.self, from: data)
            switch probe.version {
            case currentVersion:
                return .loaded(try JSONDecoder().decode(ChecklistEnvelope.self, from: data))
            case 1:
                let legacy = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
                return .migratable(from: 1, checklists: legacy.checklists)
            default:
                logger.error("Unsupported checklist payload version \(probe.version, privacy: .public); treating as empty")
                return .unsupportedVersion
            }
        } catch {
            logger.error("Failed to decode checklist payload: \(error.localizedDescription, privacy: .public)")
            return .unreadable
        }
    }

    static func decode(_ data: Data) -> [Checklist] {
        switch classify(data) {
        case .loaded(let envelope): return envelope.checklists
        case .migratable(_, let checklists): return checklists
        case .unsupportedVersion, .unreadable: return []
        }
    }

    private struct VersionProbe: Decodable { let version: Int }
}
```

Keep `.unsupportedVersion` free of associated values so the existing
`ChecklistCodecTests` comparison still compiles.

#### 3. Store learns deviceID, envelopes, and v1 migration
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

```swift
init(
    defaults: UserDefaults = AppGroup.defaults,
    key: String = "checklists.v1",
    textEditDelay: Duration? = .milliseconds(300),
    now: @escaping () -> Date = Date.init
) {
    self.defaults = defaults
    self.key = key
    self.textEditDelay = textEditDelay
    self.now = now

    if let existing = defaults.string(forKey: Self.deviceIDKey) {
        self.deviceID = existing
    } else {
        let created = UUID().uuidString
        defaults.set(created, forKey: Self.deviceIDKey)
        self.deviceID = created
    }

    if let data = defaults.data(forKey: key) {
        switch ChecklistCodec.classify(data) {
        case .loaded(let stored):
            self.checklists = stored.checklists
            self.canOverwriteStoredPayload = true
        case .migratable(_, let legacy):
            self.checklists = legacy.map { $0.migrated(at: now()) }
            self.canOverwriteStoredPayload = true   // never stall migration
        case .unsupportedVersion:
            self.checklists = []
            self.canOverwriteStoredPayload = false
        case .unreadable:
            self.checklists = []
            self.canOverwriteStoredPayload = true
        }
    } else {
        self.checklists = []
        self.canOverwriteStoredPayload = true
    }
}

let deviceID: String                       // internal so tests can assert stability
var envelope: ChecklistEnvelope {
    ChecklistEnvelope(version: ChecklistCodec.currentVersion,
                      deviceID: deviceID,
                      checklists: checklists)
}
var canAcceptRemoteChanges: Bool { canOverwriteStoredPayload }

private static let deviceIDKey = "checklist.deviceID"
@ObservationIgnored private let now: () -> Date
```

In `save()`, replace `ChecklistCodec.encode(checklists)` with
`ChecklistCodec.encode(envelope)`. (Tombstones arrive in Stage 4.)

### Verification
#### Automated
- [x] `make test-unit` passes (full unit target)
- [x] `xcodebuild -scheme CheckStitch -destination platform=macOS -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests/ChecklistCodecTests -only-testing:CheckStitchTests/ChecklistStoreTests test` passes

#### Manual
- [ ] Read the rewritten codec tests and confirm the v1 fixture contains **no** `deviceID`, `tombstones`, `modifiedAt`, or `revision` keys (a true legacy payload)

---

## Phase 2 — Sync transport seam (`ChecklistSyncing`)

### Changes

#### 1. Core seam + real adapter
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift`
**Action**: create

Domain-free (`Data`-in/`Data`-out) so it needs no app-target model. Mirrors
`ReminderCreating`'s protocol + `@MainActor` adapter shape.

```swift
import Foundation

/// Seam over the iCloud key-value store the checklist payload travels through.
/// `Data`-only so it carries no app-target model.
@MainActor
public protocol ChecklistSyncing: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func synchronize()
    @discardableResult
    func startObserving(_ onChange: @escaping @MainActor () -> Void) -> any ChecklistSyncObservation
}

/// Cancels a change subscription. Cancelling a token twice is allowed.
@MainActor
public protocol ChecklistSyncObservation: Sendable {
    func cancel()
}

/// Real adapter over one long-lived `NSUbiquitousKeyValueStore` and one key.
@MainActor
public final class UbiquitousChecklistSync: ChecklistSyncing {
    public init(store: NSUbiquitousKeyValueStore = .default, key: String = "checklists.v1") {
        self.store = store
        self.key = key
    }

    public func read() throws -> Data? { store.data(forKey: key) }
    public func write(_ data: Data) throws { store.set(data, forKey: key) }
    public func synchronize() { _ = store.synchronize() }

    @discardableResult
    public func startObserving(_ onChange: @escaping @MainActor () -> Void) -> any ChecklistSyncObservation {
        let token = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { _ in
            // The notification can arrive off-main; hop before calling back.
            MainActor.assumeIsolated { onChange() }
        }
        return NotificationObservation(token: token)
    }

    private let store: NSUbiquitousKeyValueStore
    private let key: String
}

/// Removes the NotificationCenter observer on `cancel()`.
@MainActor
private final class NotificationObservation: ChecklistSyncObservation {
    init(token: NSObjectProtocol) { self.token = token }
    func cancel() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
    private var token: NSObjectProtocol?
}
```

#### 2. Entitlement
**File**: `CheckStitch/AppGroup.entitlements`
**Action**: modify

Add one key (the pbxproj already points `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]`
and `[sdk=iphonesimulator*]` at this file, so no pbxproj edit is needed):

```xml
	<key>com.apple.developer.ubiquity-kvstore-identifier</key>
	<string>$(TeamIdentifierPrefix)app.alanvardy.CheckStitch</string>
```

#### 3. Test double
**File**: `CheckStitchTests/TestFixtures.swift`
**Action**: modify

Add after `SpyReminderCreator`:

```swift
/// Test double for `ChecklistSyncing`: in-memory bytes, recorded writes, and a
/// manually-fired external-change callback.
@MainActor
final class InMemoryChecklistSync: ChecklistSyncing {
    var stored: Data?
    var readError: Error?
    var writeError: Error?
    private(set) var written: [Data] = []
    private(set) var synchronizeCount = 0
    private(set) var readCount = 0
    private var onChange: (@MainActor () -> Void)?

    init(stored: Data? = nil) { self.stored = stored }

    func read() throws -> Data? {
        readCount += 1
        if let readError { throw readError }
        return stored
    }
    func write(_ data: Data) throws {
        if let writeError { throw writeError }
        written.append(data)
        stored = data
    }
    func synchronize() { synchronizeCount += 1 }
    @discardableResult
    func startObserving(_ onChange: @escaping @MainActor () -> Void) -> any ChecklistSyncObservation {
        self.onChange = onChange
        return InMemoryObservation()
    }
    func fireExternalChange() { onChange?() }
}

@MainActor
final class InMemoryObservation: ChecklistSyncObservation {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}
```

#### 4. Adapter canary
**File**: `CheckStitchTests/UbiquitousChecklistSyncTests.swift`
**Action**: create

```swift
import CheckStitchCore
import Testing

@MainActor
struct UbiquitousChecklistSyncTests {
    @Test
    func realAdapterCanBeConstructed() {
        // Construction canary only: no read/write/synchronize is called, so no
        // KVS API runs in the test host.
        _ = UbiquitousChecklistSync()
    }
}
```

### Verification
#### Automated
- [ ] `make test-unit` passes (new canary + existing suites)
- [ ] `make build-mac` passes (unsigned macOS leg still compiles the Core seam and `NSUbiquitousKeyValueStore` usage)
- [ ] `xcodebuild -scheme CheckStitch -destination platform=macOS -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests/UbiquitousChecklistSyncTests test` passes

#### Manual
- [ ] Inspect `CheckStitch/AppGroup.entitlements` and confirm the new key uses `$(TeamIdentifierPrefix)app.alanvardy.CheckStitch`

---

## Phase 3 — Merge engine (pure)

### Changes

#### 1. `ChecklistMerge`
**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: create

Pure and dependency-free. Winner rule: higher `revision`, then newer
`modifiedAt`, then the lexicographically smaller envelope `deviceID` (so both
sides compute the same winner regardless of argument order). Tombstones union by
`(checklistID, itemID)` and always suppress their live entry.

```swift
import Foundation

enum ChecklistMerge {
    static func merge(local: ChecklistEnvelope, remote: ChecklistEnvelope) -> ChecklistEnvelope {
        let tombstones = mergedTombstones(local.tombstones, remote.tombstones)
        let deadChecklists = Set(tombstones.filter { $0.itemID == nil }.map(\.checklistID))
        let itemTombstones = tombstones.filter { $0.itemID != nil }

        var checklists = mergedChecklists(
            local.checklists, remote.checklists,
            localDevice: local.deviceID, remoteDevice: remote.deviceID
        )
        checklists.removeAll { deadChecklists.contains($0.id) }
        for index in checklists.indices {
            let deadItems = Set(
                itemTombstones.filter { $0.checklistID == checklists[index].id }.compactMap(\.itemID)
            )
            checklists[index].items.removeAll { deadItems.contains($0.id) }
        }

        return ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: local.deviceID,
            checklists: checklists,
            tombstones: tombstones
        )
    }

    private struct TombstoneKey: Hashable {
        let checklistID: UUID
        let itemID: UUID?
    }

    private static func mergedTombstones(
        _ local: [ChecklistTombstone], _ remote: [ChecklistTombstone]
    ) -> [ChecklistTombstone] {
        var byKey: [TombstoneKey: ChecklistTombstone] = [:]
        for tombstone in local + remote {
            let key = TombstoneKey(checklistID: tombstone.checklistID, itemID: tombstone.itemID)
            if let existing = byKey[key] {
                if wins(revision: tombstone.revision, date: tombstone.deletedAt,
                        overRevision: existing.revision, overDate: existing.deletedAt) {
                    byKey[key] = tombstone
                }
            } else {
                byKey[key] = tombstone
            }
        }
        // Deterministic order so re-merging an unchanged payload is a no-op.
        return byKey.values.sorted {
            ($0.checklistID.uuidString, $0.itemID?.uuidString ?? "")
                < ($1.checklistID.uuidString, $1.itemID?.uuidString ?? "")
        }
    }

    private static func mergedChecklists(
        _ local: [Checklist], _ remote: [Checklist],
        localDevice: String, remoteDevice: String
    ) -> [Checklist] {
        var result = local
        var indexByID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) })
        for remoteChecklist in remote {
            guard let index = indexByID[remoteChecklist.id] else {
                indexByID[remoteChecklist.id] = result.count
                result.append(remoteChecklist)
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
            merged.items = mergedItems(
                localChecklist.items, remoteChecklist.items,
                localDevice: localDevice, remoteDevice: remoteDevice
            )
            result[index] = merged
        }
        return result
    }

    private static func mergedItems(
        _ local: [ChecklistItem], _ remote: [ChecklistItem],
        localDevice: String, remoteDevice: String
    ) -> [ChecklistItem] {
        var result = local
        var indexByID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) })
        for remoteItem in remote {
            guard let index = indexByID[remoteItem.id] else {
                indexByID[remoteItem.id] = result.count
                result.append(remoteItem)
                continue
            }
            let localItem = result[index]
            if wins(revision: remoteItem.revision, date: remoteItem.modifiedAt, device: remoteDevice,
                    overRevision: localItem.revision, overDate: localItem.modifiedAt, overDevice: localDevice) {
                result[index] = remoteItem
            }
        }
        return result
    }

    private static func wins(revision: Int, date: Date, device: String? = nil,
                             overRevision: Int, overDate: Date, overDevice: String? = nil) -> Bool {
        if revision != overRevision { return revision > overRevision }
        if date != overDate { return date > overDate }
        guard let device, let overDevice else { return false }
        return device < overDevice
    }
}
```

#### 2. Merge tests
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: create

Swift Testing, `@MainActor`. Local helpers `env(_:device:tombstones:)` and item/list
builders with explicit ids/revisions.

```swift
import Testing
@testable import CheckStitch

@MainActor
struct ChecklistMergeTests {
    @Test func disjointChecklistsAreUnitedLocalOrderFirst() { ... }
    @Test func higherRevisionWinsInEitherArgumentOrder() { ... }
    @Test func equalRevisionAndTimestampBreakTiesByDeviceID() { ... }
    @Test func tombstonedChecklistIsNeverResurrected() { ... }
    @Test func tombstonedItemIsRemovedFromLiveChecklist() { ... }
    @Test func itemEditsFromBothDevicesSurvive() { ... }
    @Test func sameItemEditedOnBothDevicesUsesLWW() { ... }
    @Test func identicalEnvelopesAreANoOp() { ... }
}
```

Key assertions:
- `disjoint…`: merged order `[local, remoteOnly]`; both ids present.
- `higherRevision…`: same id, local rev 2 / remote rev 1 → local name; reversed arguments → still the rev-2 name.
- tie-break: equal rev + equal date, devices `"device-a"`/`"device-b"` → `"device-a"` wins in both argument orders.
- tombstone: live checklist rev 5 + remote checklist tombstone rev 1 → checklist absent, tombstone retained.
- item edits: two distinct item ids → both survive; same item id on both → LWW winner.

### Verification
#### Automated
- [ ] `make test-unit` passes
- [ ] `xcodebuild -scheme CheckStitch -destination platform=macOS -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests/ChecklistMergeTests test` passes

#### Manual
- [ ] Confirm `ChecklistMerge.swift` imports only `Foundation` (no store, no seam, no I/O)

---

## Phase 4 — Store reconciliation & tombstones

### Changes

#### 1. Store owns tombstones, stamping, `apply`, and `onChange`
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

New state and entry points:

```swift
private(set) var tombstones: [ChecklistTombstone] = []
/// Invoked after every persisted save, except saves that are applying remote
/// state (the coordinator pushes those itself).
@ObservationIgnored var onChange: (() -> Void)?
@ObservationIgnored private var isApplyingRemote = false
```

`ChecklistStore.init` (`case .loaded`) must also load `self.tombstones =
stored.tombstones`; the `.migratable` and empty paths default to `[]`. The
`envelope` computed property gains `tombstones: tombstones`.

Every mutation stamps the mutated entity; deletes persist tombstones instead of
only dropping rows:

```swift
@discardableResult
func create() -> Checklist {
    let checklist = Checklist(modifiedAt: now(), revision: 1)
    checklists.append(checklist)
    save()
    return checklist
}

func rename(id: UUID, to name: String) {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
    checklists[index].name = name
    checklists[index].revision += 1
    checklists[index].modifiedAt = now()
    scheduleSave()
}

func addItem(to id: UUID) {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
    checklists[index].items.append(ChecklistItem(title: "New item", modifiedAt: now(), revision: 1))
    save()
}

func updateItem(checklistID: UUID, itemID: UUID, title: String) {
    guard let checklistIndex = checklists.firstIndex(where: { $0.id == checklistID }),
          let itemIndex = checklists[checklistIndex].items.firstIndex(where: { $0.id == itemID })
    else { return }
    checklists[checklistIndex].items[itemIndex].title = title
    checklists[checklistIndex].items[itemIndex].revision += 1
    checklists[checklistIndex].items[itemIndex].modifiedAt = now()
    scheduleSave()
}

func removeItems(from id: UUID, at offsets: IndexSet) {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
    for offset in offsets.sorted(by: >) {
        guard checklists[index].items.indices.contains(offset) else { continue }
        let removed = checklists[index].items.remove(at: offset)
        tombstones.append(ChecklistTombstone(
            checklistID: id, itemID: removed.id, deletedAt: now(), revision: removed.revision + 1))
    }
    save()
}

/// Local-only: reminders already created in Reminders are never touched.
func delete(id: UUID) {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return }
    let removed = checklists.remove(at: index)
    tombstones.append(ChecklistTombstone(
        checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
    save()
}

/// Merges a remote payload into local state. Refuses (no save, no state change)
/// when the stored payload came from a newer app version, preserving the
/// never-overwrite-newer guard. Returns whether visible state changed.
@discardableResult
func apply(remote: ChecklistEnvelope) -> Bool {
    guard canOverwriteStoredPayload else { return false }
    guard remote.version == ChecklistCodec.currentVersion else { return false }
    let merged = ChecklistMerge.merge(local: envelope, remote: remote)
    guard merged != envelope else { return false }   // idempotent
    let visibleChanged = merged.checklists != checklists
    isApplyingRemote = true
    checklists = merged.checklists
    tombstones = merged.tombstones
    save()
    isApplyingRemote = false
    return visibleChanged
}
```

`save()` encodes `envelope` and notifies only for local mutations:

```swift
do {
    defaults.set(try ChecklistCodec.encode(envelope), forKey: key)
    if !isApplyingRemote { onChange?() }
} catch { ... }
```

#### 2. Store tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

Add a controllable clock helper and new cases (keep every existing case intact):

```swift
/// Deterministic clock so revision/timestamp assertions are exact.
private final class Clock { var now = Date(timeIntervalSince1970: 0) }
```

New cases (XCTest, `@MainActor`):
- `testLegacyPayloadIsMigratedAndSavable` — seed the v1 fixture, build the store, assert the migrated revisions are `1` and the item's too; then `store.create()`; reload → 2 checklists. **This is the regression test for the stalled-migration risk and is written before Stage-1 changes.**
- `testDeviceIDIsStableAcrossInstances` — two stores over the same `UserDefaults` share `deviceID`.
- `testNewPayloadIsVersionTwo` — after a mutation, `ChecklistCodec.classify(data)` is `.loaded` and the envelope `version == 2`.
- `testMutationsStampRevisionAndTimestamp` — injected `Clock`; `create` → checklist rev 1 / t0; advance clock; `rename` → rev 2 / t1; `addItem` → item rev 1 / t1; `updateItem` → item rev 2.
- `testDeleteLeavesChecklistTombstone` — tombstone with `itemID == nil`; live row gone; reload preserves the tombstone.
- `testRemoveItemsLeavesItemTombstones` — tombstone per removed id; live rows gone.
- `testApplyMergesRemoteChecklist` — remote-only checklist appears, returns `true`, and reload shows it.
- `testApplyPropagatesRemoteTombstone` — local checklist removed by a remote tombstone.
- `testApplyIsIdempotent` — second `apply` of the same remote returns `false` and leaves the stored data unchanged.
- `testApplyRefusesFutureVersion` — `version: 99` envelope → `false`, state and stored bytes unchanged.
- `testEnvelopeRoundTripsThroughCodec` — `ChecklistCodec.classify(try encode(store.envelope)) == .loaded(store.envelope)`.

### Verification
#### Automated
- [ ] `make test-unit` passes, including every pre-existing `ChecklistStoreTests` case (reload, corrupt repair, unsupported-version refusal, debounce/flush)
- [ ] `xcodebuild -scheme CheckStitch -destination platform=macOS -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests/ChecklistStoreTests test` passes

#### Manual
- [ ] Confirm `canOverwriteStoredPayload` is still only ever *read* by `save`/`apply` and is never set false for `.migratable`

---

## Phase 5 — Sync coordinator & app wiring

### Changes

#### 1. `ChecklistSyncService`
**File**: `CheckStitch/ChecklistSyncService.swift`
**Action**: create

```swift
import Foundation
import Observation

enum SyncOutcome: Equatable, Sendable {
    case synced
    case seeded
    case unavailable
    case failed(String)
}

@MainActor
@Observable
final class ChecklistSyncService {
    static let didSeedKey = "checklist.sync.didSeedCloud"

    private(set) var isSyncing = false
    private(set) var lastOutcome: SyncOutcome?

    private let sync: any ChecklistSyncing
    private let store: ChecklistStore
    private let defaults: UserDefaults
    private let pushDelay: Duration?

    @ObservationIgnored private var observation: (any ChecklistSyncObservation)?
    @ObservationIgnored private var inFlight: Task<SyncOutcome, Never>?
    @ObservationIgnored private var inFlightID: UUID?
    @ObservationIgnored private var pushTask: Task<Void, Never>?

    init(sync: any ChecklistSyncing,
         store: ChecklistStore,
         defaults: UserDefaults = AppGroup.defaults,
         pushDelay: Duration? = .milliseconds(500)) { ... }

    /// Wires the external-change observer and the store's local-edit callback.
    /// Call once, right after construction.
    func start() {
        observation = sync.startObserving { [weak self] in
            guard let self else { return }
            Task { await self.reconcile() }
        }
        store.onChange = { [weak self] in self?.schedulePush() }
    }

    func syncOnLaunch() async { _ = await reconcile() }

    /// Coalesces concurrent callers onto a single in-flight reconcile.
    @discardableResult
    func reconcile() async -> SyncOutcome {
        if let inFlight { return await inFlight.value }
        let id = UUID()
        let task = Task { self.reconcileNow() }
        inFlight = task
        inFlightID = id
        let outcome = await task.value
        if inFlightID == id {
            inFlight = nil
            inFlightID = nil
        }
        return outcome
    }

    /// Pull-to-refresh: ask iCloud for the latest bytes, then reconcile.
    func refresh() async -> SyncOutcome {
        sync.synchronize()
        return await reconcile()
    }

    /// Immediate push for backgrounding — must not wait out the debounce.
    func pushNow() {
        pushTask?.cancel()
        pushTask = nil
        _ = reconcileNow()
    }

    func schedulePush() {
        guard let pushDelay else { return pushNow() }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: pushDelay)
            guard !Task.isCancelled else { return }
            self?.pushNow()
        }
    }

    private func reconcileNow() -> SyncOutcome {
        isSyncing = true
        defer { isSyncing = false }

        guard store.canAcceptRemoteChanges else { return finish(.unavailable) }

        let remoteData: Data?
        do { remoteData = try sync.read() } catch { return finish(.unavailable) }

        guard let remoteData else {
            guard !defaults.bool(forKey: Self.didSeedKey) else { return finish(.synced) }
            do { try sync.write(try ChecklistCodec.encode(store.envelope)) }
            catch { return finish(.failed(error.localizedDescription)) }
            sync.synchronize()
            defaults.set(true, forKey: Self.didSeedKey)
            return finish(.seeded)
        }

        let remote: ChecklistEnvelope
        switch ChecklistCodec.classify(remoteData) {
        case .loaded(let envelope):
            remote = envelope
        case .migratable(_, let checklists):
            remote = ChecklistEnvelope(deviceID: "", checklists: checklists.map { $0.migrated(at: .distantPast) })
        case .unsupportedVersion, .unreadable:
            // Never discard local state because the remote bytes were foreign.
            return finish(.failed("Stored sync data could not be read."))
        }

        let visibleChanged = store.apply(remote: remote)
        if visibleChanged || !store.envelope.contentEquals(remote) {
            do { try sync.write(try ChecklistCodec.encode(store.envelope)) }
            catch { return finish(.failed(error.localizedDescription)) }
            sync.synchronize()
        }
        defaults.set(true, forKey: Self.didSeedKey)
        return finish(.synced)
    }

    private func finish(_ outcome: SyncOutcome) -> SyncOutcome {
        lastOutcome = outcome
        return outcome
    }
}
```

#### 2. Wire production
**File**: `CheckStitch/MyApp.swift`
**Action**: modify

```swift
import CheckStitchCore

@main struct MyApp: App {
    ...
    @State private var store: ChecklistStore
    @State private var syncService: ChecklistSyncService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ChecklistStore()
        let syncService = ChecklistSyncService(sync: UbiquitousChecklistSync(), store: store)
        syncService.start()
        _store = State(initialValue: store)
        _syncService = State(initialValue: syncService)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(syncService)
                .task { await syncService.syncOnLaunch() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Flush coalesced text edits and push before the app suspends.
            if phase != .active {
                store.flushPendingSave()
                syncService.pushNow()
            }
        }
        // macOS branch additionally keeps `.restorationBehavior(.disabled)`.
    }
}
```

(The macOS branch adds `.restorationBehavior(.disabled)` to its `WindowGroup`
exactly as today; only the content and `onChange` change.)

#### 3. Service tests
**File**: `CheckStitchTests/ChecklistSyncServiceTests.swift`
**Action**: create

Swift Testing, `@MainActor`, isolated defaults, `pushDelay: nil`, and an
`envelopeData(_:deviceID:)` helper that encodes a `ChecklistEnvelope`.

```swift
import CheckStitchCore
import Testing
@testable import CheckStitch

@MainActor
struct ChecklistSyncServiceTests {
    @Test func cloudEmptySeedsLocalOnce() { ... }
    @Test func localEmptyAppliesRemote() { ... }
    @Test func bothNonEmptyMergeAndPush() { ... }
    @Test func readFailureIsUnavailable() { ... }
    @Test func writeFailureIsSurfacedAsFailed() { ... }
    @Test func concurrentRefreshesCoalesceIntoOneRead() { ... }
    @Test func unreadableRemoteIsIgnored() { ... }
    @Test func observerCallbackTriggersReconcile() { ... }
}
```

Key assertions:
- seeding: first `syncOnLaunch()` → `.seeded`, `defaults.bool(forKey: ChecklistSyncService.didSeedKey)` true, `sync.written.count == 1`; second `reconcile()` → `.synced`, still 1 write.
- local-empty: remote bytes hold one checklist → after `reconcile()` the store contains it.
- both non-empty: store has A, remote has B → store has A+B and `sync.written.count == 1`.
- read failure: `sync.readError = TestError.boom` → `.unavailable`.
- write failure: `sync.writeError = TestError.boom`, empty cloud, non-empty store → `if case .failed = outcome`.
- coalescing: `async let a = service.refresh(); async let b = service.refresh(); _ = await (a, b)` → `sync.readCount == 1`.
- unreadable remote: `sync.stored = Data("not json".utf8)`; store keeps its checklist; no write.
- observer: `service.start()`; remote holds a checklist; `sync.fireExternalChange()`; `try await Task.sleep(for: .milliseconds(50))`; store contains the remote checklist.

### Verification
#### Automated
- [ ] `make test-unit` passes
- [ ] `make build` passes (app compiles with the service constructed and injected in `MyApp`)
- [ ] `xcodebuild -scheme CheckStitch -destination platform=macOS -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests/ChecklistSyncServiceTests test` passes

#### Manual
- [ ] Confirm `UbiquitousChecklistSync` is constructed in `MyApp` (the new seam is not a repeat of the dead `AppEnvironment` wiring gap)

---

## Phase 6 — Pull-to-refresh UI

### Changes

#### 1. `ContentView` gains refresh + status surface
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

- Add `@Environment(ChecklistSyncService.self) private var syncService`.
- Add a bottom status inset on the empty/list `Group`:

```swift
Group {
    if store.checklists.isEmpty { emptyState } else { checklistList }
}
.safeAreaInset(edge: .bottom) {
    SyncStatusView(outcome: syncService.lastOutcome, isSyncing: syncService.isSyncing)
}
```

- Attach `.refreshable` to the `ScrollView` inside `checklistList`:

```swift
ScrollView { LazyVStack(spacing: 0) { ... } }
    .refreshable { await syncService.refresh() }
```

- Add the status component at the bottom of the file:

```swift
/// Honest sync feedback: nothing when healthy, an activity line while syncing,
/// and the failure reason otherwise.
struct SyncStatusView: View {
    let outcome: SyncOutcome?
    let isSyncing: Bool

    /// Text shown under the list; `nil` when there is nothing to report.
    var message: String? {
        if isSyncing { return "Syncing…" }
        if case .failed(let reason) = outcome { return reason }
        return nil
    }

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                if isSyncing { ProgressView().controlSize(.small) }
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(8)
            .accessibilityIdentifier("syncStatusView")
        }
    }
}
```

- Update `#Preview` to inject the service:

```swift
#Preview {
    let store = ChecklistStore()
    ContentView()
        .environment(store)
        .environment(ChecklistSyncService(sync: UbiquitousChecklistSync(), store: store))
}
```

#### 2. Render tests
**File**: `CheckStitchTests/ViewRenderTests.swift`
**Action**: modify

```swift
@Test func syncStatusIsSilentWhenSynced() {
    #expect(SyncStatusView(outcome: .synced, isSyncing: false).message == nil)
}

@Test func syncStatusShowsFailureReason() {
    #expect(SyncStatusView(outcome: .failed("boom"), isSyncing: false).message == "boom")
}

@Test func syncStatusShowsActivityWhileSyncing() {
    #expect(SyncStatusView(outcome: nil, isSyncing: true).message != nil)
}
```

#### 3. UI smoke
**File**: `CheckStitchUITests/CheckStitchUITests.swift`
**Action**: none (verify unchanged)

The smoke case stays exactly as-is; the new bottom inset must not displace the
existing accessible buttons.

### Verification
#### Automated
- [ ] `make test-unit` passes (render tests green)
- [ ] `make test-ui` passes (one-shot smoke, on this worktree's `.simulator_id`)
- [ ] `bash scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Two devices signed into the same iCloud account (pinned simulator + a physical device via `bash scripts/run-devices.sh`): create a checklist with items on device A, background it, then on device B pull-to-refresh and confirm the checklist and items appear
- [ ] Rename the checklist and delete an item on device B, pull-to-refresh on device A, confirm the rename and the removal propagate
- [ ] Delete a checklist on device A, pull-to-refresh on device B, confirm it disappears locally
- [ ] Confirm no Reminders are created or removed by any sync operation (check the inbox before/after)
- [ ] With iCloud signed out / KVS unavailable, confirm the app still works and the failure banner is shown rather than data being lost

---

## Testing Checkpoints

After **each** stage, `make test-unit` must be green before starting the next.

- [x] After Stage 1 → codec/store suites green; a v1 payload loads, migrates, and can be saved over.
- [ ] After Stage 2 → seam fake + adapter canary green; `make build-mac` green.
- [ ] After Stage 3 → merge suite green (pure, no I/O).
- [ ] After Stage 4 → store suite green, including all unchanged legacy cases.
- [ ] After Stage 5 → service suite green and the app builds with the service wired in `MyApp`.
- [ ] After Stage 6 → `bash scripts/test.sh` prints `gate: ok`; two-device round-trip verified manually.

## Files Touched (summary)

| File | Action | Phase |
|---|---|---|
| `CheckStitch/Checklist.swift` | modify | 1 |
| `CheckStitch/ChecklistStore.swift` | modify | 1, 4 |
| `CheckStitch/ChecklistMerge.swift` | create | 3 |
| `CheckStitch/ChecklistSyncService.swift` | create | 5 |
| `CheckStitch/MyApp.swift` | modify | 5 |
| `CheckStitch/ContentView.swift` | modify | 6 |
| `CheckStitch/AppGroup.entitlements` | modify | 2 |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift` | create | 2 |
| `CheckStitchTests/TestFixtures.swift` | modify | 2 |
| `CheckStitchTests/ChecklistCodecTests.swift` | modify | 1 |
| `CheckStitchTests/ChecklistStoreTests.swift` | modify | 1, 4 |
| `CheckStitchTests/ChecklistMergeTests.swift` | create | 3 |
| `CheckStitchTests/UbiquitousChecklistSyncTests.swift` | create | 2 |
| `CheckStitchTests/ChecklistSyncServiceTests.swift` | create | 5 |
| `CheckStitchTests/ViewRenderTests.swift` | modify | 6 |
| `CheckStitchUITests/CheckStitchUITests.swift` | unchanged | 6 |

No `project.pbxproj` edit is needed: new app files are picked up by
`PBXFileSystemSynchronizedRootGroup` and new Core files by the SPM target.