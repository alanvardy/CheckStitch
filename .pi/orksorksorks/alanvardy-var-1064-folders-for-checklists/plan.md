# Implementation Plan

## Overview

Add a `Folder` entity and a `Checklist.folderID` relationship inside the
existing `checklists.v1` envelope (bumped v4 → v5), then ship it as vertical
tracer slices: a folder that holds a real checklist end to end, then folder
merge/sync, rename/reorder, delete/orphan, watch sections, and finally
hardening + localization.

The plan never reorganizes the phase order from `structure.md`. Two additions
are noted as deviations in the summary: the v5 bump forces mechanical
`ChecklistCodec.classify`/test updates that `structure.md` did not list, and
Phase 5 must include the phone→watch folder transport (`ChecklistSyncCoordinator`,
`WatchChecklistStore`, `MyApp`) or the watch has folder ids but no names.

**Scope guard**: folders ride in the existing envelope; no second store/key, no
per-folder member ordering, no drawer of folder strings in Core (grouping is
string-free), no import/export folder support, no context menus/swipe actions.

---

## Phase 1: Walking skeleton — a folder exists and holds a checklist, end to end

### Changes

#### 1. New value types + envelope fields + codec version
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Add beside `ChecklistTombstone`:

```swift
/// A named group that checklists can be filed under. `revision`/`modifiedAt`
/// carry the same last-write-wins identity `Checklist` uses, so folder renames
/// and deletes converge through `ChecklistMerge`.
public struct Folder: Identifiable, Codable, Hashable, Sendable {
    public init(id: UUID = UUID(), name: String = "New Folder",
                modifiedAt: Date = .distantPast, revision: Int = 0) {
        self.id = id
        self.name = name
        self.modifiedAt = modifiedAt
        self.revision = revision
    }

    public let id: UUID
    public var name: String
    public var modifiedAt: Date
    public var revision: Int
}

/// A persisted folder-deletion record. Mirrors `ChecklistTombstone`: it only
/// grows, and suppresses its live folder under `ChecklistMerge`.
public struct FolderTombstone: Codable, Hashable, Sendable {
    public init(folderID: UUID, deletedAt: Date, revision: Int) {
        self.folderID = folderID
        self.deletedAt = deletedAt
        self.revision = revision
    }

    public let folderID: UUID
    public var deletedAt: Date
    public var revision: Int
}
```

On `Checklist` add `public var folderID: UUID?` (a one-field relationship, sharing
the checklist's coarse clock — like `destinationListIdentifier`):
- init parameter `folderID: UUID? = nil` after `prefixesReminderNumbers`, assigned.
- `CodingKeys` gain `case folderID`.
- `init(from:)` decodes `let folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)` and passes it to the public init.
- `encode(to:)` writes it unconditionally (matching the `relativeDate` shape):

```swift
if let folderID {
    try container.encode(folderID, forKey: .folderID)
} else {
    try container.encodeNil(forKey: .folderID)
}
```

On `ChecklistEnvelope`:
- add `public var folders: [Folder]` and `public var folderTombstones: [FolderTombstone]`;
- `init(..., folders: [Folder] = [], folderTombstones: [FolderTombstone] = [])` (defaulted so every existing call site keeps compiling);
- `CodingKeys` gain `case folders, folderTombstones`;
- `init(from:)` uses `decodeIfPresent(...) ?? []` for both (the `tombstones` shape);
- `encode(to:)` writes both unconditionally;
- `contentEquals` includes `folders == other.folders && folderTombstones == other.folderTombstones`.

On `ChecklistCodec`:
```swift
public static let currentVersion = 5
```
and in `classify` add, above `case 3`:
```swift
case 4:
    // v4 carries full sync and ordering state, but predates folders. Load
    // verbatim, never restamp; absent folder keys decode to []/nil.
    let previous = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
    return .migratable(from: 4, envelope: previous)
```

#### 2. Store: persisted folders + membership move
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

Add state and wire it through load/envelope/apply:
```swift
private(set) var folders: [Folder] = []
private(set) var folderTombstones: [FolderTombstone] = []
```

In `init` load switch: `.loaded` → `folders = stored.folders; folderTombstones = stored.folderTombstones`; every `.migratable` branch (after the `checklists` switch) → `folders = legacy.folders; folderTombstones = legacy.folderTombstones`; `.unsupportedVersion`/`.unreadable`/no-data → both default `[]`.

`envelope` getter:
```swift
ChecklistEnvelope(version: ChecklistCodec.currentVersion,
                  deviceID: deviceID,
                  checklists: checklists,
                  tombstones: tombstones,
                  folders: folders,
                  folderTombstones: folderTombstones)
```

`apply(remote:)` assigns folders after `checklists`/`tombstones`:
```swift
folders = merged.folders
folderTombstones = merged.folderTombstones
```

New mutations (place beside `create`/`moveChecklists`):
```swift
/// Creates a folder, disambiguating the name like `create` ("New Folder 2").
/// Always succeeds; returns the folder so a caller could open/rename it.
@discardableResult
func createFolder(name: String? = nil) -> Folder {
    let folder = Folder(name: Self.uniqueName(basedOn: name ?? "New Folder", taken: folders.map(\.name)),
                        modifiedAt: now(), revision: 1)
    folders.append(folder)
    save()
    return folder
}

/// Files a checklist into `folderID` (`nil` = loose). Bumps the checklist's
/// coarse revision/`modifiedAt` so the membership wins the LWW round and
/// transfers through `ChecklistMerge` (no separate clock; mirrors `rename`).
/// Returns false for an unknown checklist or unknown folder; an unchanged
/// membership is a no-op (never a spurious LWW win).
@discardableResult
func moveChecklist(id: UUID, toFolder folderID: UUID?) -> Bool {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return false }
    if let folderID, !folders.contains(where: { $0.id == folderID }) { return false }
    guard checklists[index].folderID != folderID else { return true }
    checklists[index].folderID = folderID
    checklists[index].revision += 1
    checklists[index].modifiedAt = now()
    save()
    return true
}
```

#### 3. Merge: folder union + the explicit `folderID` copy line
**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: modify

In `mergedChecklists`' remote-wins block add:
```swift
merged.folderID = remoteChecklist.folderID
```

In `merge(local:remote:)`, after the checklist pruning block, union and prune folders:
```swift
let folderTombstones = mergedFolderTombstones(local.folderTombstones, remote.folderTombstones)
let deadFolders = Set(folderTombstones.map(\.folderID))
var folders = mergedFolders(local.folders, remote.folders,
                            localDevice: local.deviceID, remoteDevice: remote.deviceID)
folders.removeAll { deadFolders.contains($0.id) }

return ChecklistEnvelope(
    version: ChecklistCodec.currentVersion,
    deviceID: local.deviceID,
    checklists: checklists,
    tombstones: tombstones,
    folders: folders,
    folderTombstones: folderTombstones)
```

New private helpers mirroring `mergedChecklists`/`mergedTombstones`:
```swift
private static func mergedFolders(
    _ local: [Folder], _ remote: [Folder],
    localDevice: String, remoteDevice: String
) -> [Folder] {
    var result = local
    var indexByID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) })
    for remoteFolder in remote {
        guard let index = indexByID[remoteFolder.id] else {
            indexByID[remoteFolder.id] = result.count
            result.append(remoteFolder)          // local-first, remote-only appends
            continue
        }
        let localFolder = result[index]
        var merged = localFolder
        if wins(revision: remoteFolder.revision, date: remoteFolder.modifiedAt,
                device: remoteDevice,
                overRevision: localFolder.revision, overDate: localFolder.modifiedAt,
                overDevice: localDevice) {
            merged.name = remoteFolder.name
            merged.revision = remoteFolder.revision
            merged.modifiedAt = remoteFolder.modifiedAt
        }
        result[index] = merged
    }
    return result
}

private static func mergedFolderTombstones(
    _ local: [FolderTombstone], _ remote: [FolderTombstone]
) -> [FolderTombstone] {
    var byID: [UUID: FolderTombstone] = [:]
    for tombstone in local + remote {
        if let existing = byID[tombstone.folderID] {
            if wins(revision: tombstone.revision, date: tombstone.deletedAt,
                    overRevision: existing.revision, overDate: existing.deletedAt) {
                byID[tombstone.folderID] = tombstone
            }
        } else {
            byID[tombstone.folderID] = tombstone
        }
    }
    // Deterministic order so re-merging is a no-op.
    return byID.values.sorted { $0.folderID.uuidString < $1.folderID.uuidString }
}
```

Tombstoning a folder never touches its checklists — members keep their
`folderID` and degrade to loose at read time (Phase 6 fallback), so nothing is
dropped.

#### 4. Sync-service migration pass-through
**File**: `CheckStitch/ChecklistSyncService.swift`
**Action**: modify

The `case .migratable` `default` branch rebuilds a current-version envelope; carry
folders through it (v3/v4 payloads have none, but this keeps the shape complete):
```swift
remote = ChecklistEnvelope(
    deviceID: legacy.deviceID,
    checklists: legacy.checklists,
    tombstones: legacy.tombstones,
    folders: legacy.folders,
    folderTombstones: legacy.folderTombstones)
```

#### 5. View model
**File**: `CheckStitch/ChecklistListViewModel.swift`
**Action**: modify

```swift
var folders: [Folder] { store.folders }

/// Members of `folder` in persisted global order. `nil` is the loose group:
/// checklists with no folder, plus any whose `folderID` names a folder that is
/// not (yet) known — cross-reference skew renders loose, never dropped.
func checklists(in folder: Folder?) -> [Checklist] {
    guard let folder else {
        let known = Set(store.folders.map(\.id))
        return store.checklists.filter { checklist in
            guard let folderID = checklist.folderID else { return true }
            return !known.contains(folderID)
        }
    }
    return store.checklists.filter { $0.folderID == folder.id }
}

@discardableResult
func createFolder(name: String? = nil) -> UUID {
    store.createFolder(name: name).id
}

func moveChecklist(id: UUID, toFolder folderID: UUID?) {
    store.moveChecklist(id: id, toFolder: folderID)
}
```

#### 6. Main screen: folder sections + move control
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Replace the `LazyVStack` body of `checklistList` with a folder-first render:
```swift
LazyVStack(spacing: 0) {
    ForEach(listVM.folders) { folder in
        folderSection(for: folder)
        Divider()
    }
    if !listVM.folders.isEmpty {
        looseHeader
    }
    ForEach(listVM.checklists(in: nil)) { checklist in
        checklistRow(for: checklist)
        if checklist.id != listVM.checklists(in: nil).last?.id { Divider() }
    }
}
```

Add (keeping all controls under `isEditing`):
```swift
@ViewBuilder
private func folderSection(for folder: Folder) -> some View {
    VStack(spacing: 0) {
        folderHeader(for: folder)
        ForEach(listVM.checklists(in: folder)) { checklist in
            checklistRow(for: checklist)
            if checklist.id != listVM.checklists(in: folder).last?.id { Divider() }
        }
    }
}

@ViewBuilder
private func folderHeader(for folder: Folder) -> some View {
    HStack(spacing: 12) {
        Image(systemName: "folder")
        Text(folder.name).frame(maxWidth: .infinity, alignment: .leading)
        if isEditing { folderEditControls(for: folder) }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
}

private var looseHeader: some View {
    HStack {
        Text("Loose").font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
}
```

Phase 1 only needs the create affordance and the per-checklist move control; the
rename/delete/up-down controls arrive in Phases 3–4 (leave `folderEditControls`
empty or omit the call until then — easiest is to add it in Phase 3 and keep
`folderHeader` without the `if isEditing` branch in Phase 1).

In `checklistRow`'s editing branch, between the name and the move chevrons, add:
```swift
Menu {
    Button("Loose") { listVM.moveChecklist(id: checklist.id, toFolder: nil) }
    ForEach(listVM.folders) { folder in
        Button(folder.name) { listVM.moveChecklist(id: checklist.id, toFolder: folder.id) }
    }
} label: {
    Image(systemName: "folder")
}
.accessibilityLabel("Move to Folder")
.accessibilityIdentifier("moveChecklistToFolder-\(checklist.id.uuidString)")
```

New-folder affordance (edit mode only):
- iOS: in the existing `#if os(iOS)` header `HStack`, when `isEditing` render a leading
  `Button("New Folder") { folderNameInput = ""; isCreatingFolder = true }`
  (identifier `newFolderButton`) with the edit toggle kept trailing.
- macOS: add a `ToolbarItem(placement: .primaryAction)` gated on
  `!listVM.checklists.isEmpty && isEditing`.
- Create alert (on the root `body`, beside the existing alerts):
```swift
.alert("New Folder", isPresented: $isCreatingFolder) {
    TextField("Folder Name", text: $folderNameInput)
        .accessibilityIdentifier("folderNameField")
    Button("Cancel", role: .cancel) {}
    Button("Done") { listVM.createFolder(name: folderNameInput) }
        .accessibilityIdentifier("confirmFolderButton")
}
```
with `@State private var isCreatingFolder = false` and `@State private var folderNameInput = ""`.

#### 7. Codec/store test updates forced by the v5 bump (mechanical)
**Files**: `CheckStitchTests/ChecklistCodecTests.swift`, `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

- `ChecklistStoreTests.testNewPayloadIsCurrentVersion`: `XCTAssertEqual(stored.version, 4)` → `5`.
- `ChecklistCodecTests.testFutureVersionIsUnsupported`: change the raw payload `{"version":5,...}` → `{"version":6,...}`.
- In `ChecklistCodecTests`, the raw additive-field payloads that assert `.loaded` now classify `.migratable(from: 4, ...)`. Change their raw `"version":4` → `"version":5` (current) so they keep testing the current-version additive guarantee:
  - `testDecodesV4PayloadWithoutPrefixesReminderNumbersAsFalse` → rename `testDecodesV5PayloadWithoutPrefixesReminderNumbersAsFalse`, payload version 5.
  - `testItemWithoutDescriptionClassifiesLoadedAsEmpty` → version 5 (comment update).
  - `testPriorityKeyAbsentStaysLoaded` → version 5.
  - `testItemWithoutFieldClocksSeedsFromCoarseClock` → version 5 (comment update).
  - `testMalformedDescriptionMakesPayloadUnreadable` / `testMalformedPriorityMakesPayloadUnreadable` are version-agnostic (`.unreadable`) — leave the raw `4`, they still pass.
- `ChecklistSyncServiceTests.swift:214` raw v4 remote stays version 4: it now exercises the v3/v4 migration path, and the assertion (`nothing pushed`) still holds because the rebuilt current-version envelope `contentEquals` the local one.

#### 8. New tests
**Files**: `CheckStitchTests/ChecklistCodecTests.swift`, `CheckStitchTests/ChecklistStoreTests.swift`, `CheckStitchTests/CheckListListViewModelTests.swift`
**Action**: modify

`ChecklistCodecTests` (XCTest):
```swift
func testV4PayloadIsClassifiedMigratable() {
    let payload = Data(#"{"version":4,"deviceID":"d","tombstones":[],"checklists":[]}"#.utf8)
    XCTAssertEqual(ChecklistCodec.classify(payload), .migratable(from: 4, envelope: ChecklistEnvelope(version: 4, deviceID: "d", checklists: [])))
}

func testV4PayloadWithoutFolderKeysDecodesWithDefaults() {
    let id = UUID().uuidString
    let payload = Data(#"{"version":4,"deviceID":"d","tombstones":[],"checklists":[{"id":"\#(id)","name":"Groceries","items":[]}]}"#.utf8)
    guard case .migratable(_, let envelope) = ChecklistCodec.classify(payload) else { return XCTFail(...) }
    XCTAssertEqual(envelope.folders, [])
    XCTAssertNil(envelope.checklists.first?.folderID)
}

func testFoldersSurviveEnvelopeRoundTrip() throws {
    let folder = Folder(name: "Work")
    let checklist = Checklist(name: "Groceries", folderID: folder.id)
    let envelope = ChecklistEnvelope(deviceID: "d", checklists: [checklist], folders: [folder])
    let data = try ChecklistCodec.encode(envelope)
    XCTAssertEqual(ChecklistCodec.classify(data), .loaded(envelope))
    XCTAssertEqual(ChecklistCodec.decode(data).first?.folderID, folder.id)
    XCTAssertTrue(String(data: data, encoding: .utf8)?.contains(#""folders""#) ?? false)
}

/// The v4 build's `classify` switch only knew versions 1...4, so a v5 payload
/// fell to its `default` → `.unsupportedVersion` (write-protect). Pinned so a
/// future bump cannot silently make v5 readable to old installs.
func testV5PayloadIsUnsupportedByAPinnedV4Decoder() throws {
    let payload = try ChecklistCodec.encode(ChecklistEnvelope(deviceID: "d", checklists: []))
    XCTAssertEqual(PinnedV4Codec.classify(payload), .unsupportedVersion)
}

private enum PinnedV4Codec {
    private struct Probe: Decodable { let version: Int }
    static func classify(_ data: Data) -> ChecklistCodec.Outcome {
        guard let probe = try? JSONDecoder().decode(Probe.self, from: data) else { return .unreadable }
        switch probe.version {
        case 1...4: return .loaded(try! JSONDecoder().decode(ChecklistEnvelope.self, from: data))
        default: return .unsupportedVersion
        }
    }
}
```

`ChecklistStoreTests` (XCTest; use `makeStore`, `defer { removePersistentDomain }`):
- `testCreateFolderPersistsAcrossReload` — create, reload, `folders.map(\.name) == ["New Folder"]`, id/revision intact.
- `testCreateFolderDisambiguatesName` — create("Work"), create("Work") → `["Work", "Work 2"]`.
- `testMoveChecklistIntoFolderPersistsAndReloads` — create folder + checklist, `moveChecklist(id:toFolder:)`, reload → `folderID == folder.id`, revision bumped to 2.
- `testMoveChecklistBackToLoosePersists` — move in, move to `nil`, reload → nil.
- `testMoveToUnknownFolderIsRejected` — `XCTAssertFalse(store.moveChecklist(id: id, toFolder: UUID()))`, `folderID` nil, revision unchanged.
- `testV4PayloadLoadsWithNoFolders` — set a v4 raw payload with a checklist, reload → `store.folders == []`, `folderTombstones == []`, `canAcceptRemoteChanges`, checklist present with `folderID == nil`.

`CheckListListViewModelTests` (Swift Testing, `@MainActor struct`):
- `folderSectionsGroupMembers` — create 2 folders + 3 checklists, move 1 into each → `checklists(in: folderA)` / `(in: folderB)` / `(in: nil)` partition correctly.
- `looseListKeepsGlobalOrder` — members retain creation order.
- `moveToFolderUpdatesGrouping` — after move, the checklist leaves loose and joins the folder.
- `moveToUnknownFolderLeavesMembershipUnchanged`.
- `unknownFolderIsRenderedAsLoose` — see Phase 6 (can be written here).

### Verification
#### Automated
- [x] `make test-unit` passes (including the mechanical v4→v5 codec/store updates)
- [x] `make build` passes under `WARNINGS_AS_ERRORS`
- [x] `bash scripts/l10n-check.sh` passes (Phase 1 adds only the "Loose" key to the App catalog + `requiredKeys` — see Phase 3 for the App entries; if "Loose" is deferred, no catalog change yet)

#### Manual
- [ ] `make run`: enter edit mode → "New Folder" appears; create "Work"; a checklist row shows the folder menu; choosing "Work" renders a "Work" section with the checklist under it and the loose group below; relaunch the app and confirm it survived
- [ ] With no folders, the list looks exactly as before (no "Loose" header)

---

## Phase 2: Folder merge/sync correctness (risk-front-loaded)

### Changes

#### 1. `Folder` field merge and tombstone pruning
**File**: `CheckStitch/ChecklistMerge.swift`
**Action**: modify (already implemented in Phase 1 — this phase is the test gate)

Phase 1 already contains `mergedFolders`/`mergedFolderTombstones`, the `folderID`
copy line, and folder pruning. Phase 2 exists to prove the semantics; only test
code changes here unless a test exposes a defect.

#### 2. Test helper gains folder parameters
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

Extend the bottom helper (line ~785) without breaking existing call sites:
```swift
private func envelope(device: String,
                      checklists: [Checklist],
                      tombstones: [ChecklistTombstone] = [],
                      folders: [Folder] = [],
                      folderTombstones: [FolderTombstone] = []) -> ChecklistEnvelope {
    ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: device,
                      checklists: checklists, tombstones: tombstones,
                      folders: folders, folderTombstones: folderTombstones)
}
```
Add a `folder(id:name:revision:modifiedAt:)` fixture mirroring `checklist(...)`.

#### 3. New tests
**File**: `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

- `remoteOnlyFolderIsUnited` — local has none, remote one → merged `folders == [remote]`, local checklists untouched.
- `folderNameConflictResolvesByWins` — same id, local rev 2 "A" vs remote rev 1 "B", both argument orders → "A".
- `folderTombstoneRemovesTheFolderAndKeepsItsMembers` — local folder + member, remote folder tombstone → merged `folders == []`, `folderTombstones` carries it, the member checklist still present (its `folderID` may stay dangling).
- `mergingTheSameFolderEnvelopeTwiceIsANoOp` — `merge(merge(local, remote), remote) == merge(local, remote)`.
- `checklistCarryingAnUnknownFolderIDSsurvives` — remote checklist with a random `folderID` and no matching folder → present in `merged.checklists` with the id intact.
- `folderTombstoneBeatsALowerRevisionLiveFolder` — live folder rev 1 + tombstone rev 2 → folder pruned.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `bash scripts/tests/run.sh` passes (shell gate, unchanged)

#### Manual
- [ ] Simulator A creates a folder + moves a checklist in; stop A, relaunch (or use a second simulator signed into the same App Group/iCloud) → the folder and membership converge and do not duplicate
- [ ] Delete the folder (after Phase 4) on one side → it stays gone after the other side re-syncs (no resurrection)

---

## Phase 3: Rename and reorder folders (edit mode)

### Changes

#### 1. Store rename + reorder
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

```swift
/// Renames a folder, disambiguating the requested name against the *other*
/// folders (so re-confirming a folder's own name is a no-op, never " 2") and
/// keeping the exact `rename` shape: bump revision + `modifiedAt`, then one save.
@discardableResult
func renameFolder(id: UUID, to name: String) -> Folder? {
    guard let index = folders.firstIndex(where: { $0.id == id }) else { return nil }
    let disambiguated = Self.uniqueName(basedOn: name, taken: folders.filter { $0.id != id }.map(\.name))
    guard !Self.sameName(folders[index].name, disambiguated) else { return folders[index] }
    folders[index].name = disambiguated
    folders[index].revision += 1
    folders[index].modifiedAt = now()
    save()
    return folders[index]
}

/// Reorders folders. Folder order *is* the persisted array order and merge
/// keeps local order (remote-only appends), so — exactly like
/// `moveChecklists` — this is local-first and stamps no revision.
func moveFolders(from offsets: IndexSet, to destination: Int) {
    guard let reordered = Self.moved(folders, from: offsets, to: destination) else { return }
    folders = reordered
    save()
}
```

#### 2. View model
**File**: `CheckStitch/ChecklistListViewModel.swift`
**Action**: modify

```swift
func renameFolder(id: UUID, to name: String) {
    store.renameFolder(id: id, to: name)
}

func moveFolder(id: UUID, up: Bool) {
    guard let index = store.folders.firstIndex(where: { $0.id == id }) else { return }
    store.moveFolders(from: IndexSet(integer: index), to: up ? index - 1 : index + 2)
}
```

#### 3. Main screen: folder header controls + rename alert
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add `folderEditControls(for:)` to the `folderHeader` editing branch (same chevron
shape as `checklistMoveControls`):
```swift
@ViewBuilder
private func folderEditControls(for folder: Folder) -> some View {
    HStack(spacing: 4) {
        Button { folderNameInput = folder.name; folderBeingRenamed = folder } label: {
            Image(systemName: "pencil")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rename Folder")
        .accessibilityIdentifier("renameFolder-\(folder.id.uuidString)")

        Button { withAnimation { listVM.moveFolder(id: folder.id, up: true) } } label: {
            Image(systemName: "chevron.up")
        }
        .buttonStyle(.plain)
        .disabled(listVM.folders.first?.id == folder.id)
        .accessibilityLabel("Move up")
        .accessibilityIdentifier("moveFolderUp-\(folder.id.uuidString)")

        Button { withAnimation { listVM.moveFolder(id: folder.id, up: false) } } label: {
            Image(systemName: "chevron.down")
        }
        .buttonStyle(.plain)
        .disabled(listVM.folders.last?.id == folder.id)
        .accessibilityLabel("Move down")
        .accessibilityIdentifier("moveFolderDown-\(folder.id.uuidString)")
    }
}
```

Rename alert (separate modifier; bindings are mutually exclusive):
```swift
@State private var folderBeingRenamed: Folder?

.alert("Rename Folder",
       isPresented: Binding(get: { folderBeingRenamed != nil },
                            set: { if !$0 { folderBeingRenamed = nil } })) {
    TextField("Folder Name", text: $folderNameInput)
        .accessibilityIdentifier("folderNameField")
    Button("Cancel", role: .cancel) { folderBeingRenamed = nil }
    Button("Done") {
        if let folder = folderBeingRenamed { listVM.renameFolder(id: folder.id, to: folderNameInput) }
        folderBeingRenamed = nil
    }
    .accessibilityIdentifier("confirmFolderButton")
}
```

#### 4. Localization keys introduced here
**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add these keys with **all six languages** (`en, de, es, fr, ja, zh-Hans`) and one
`requiredKeys` entry each under the `"App"` catalog:
- `"New Folder"` (Phase 1 button + alert title)
- `"Folder Name"` (alert TextField placeholder)
- `"Rename Folder"` (alert title + accessibility label)
- `"Loose"` (loose group header + move menu)
- `"Move to Folder"` (move menu accessibility label)

Run `bash scripts/l10n-check.sh` first to see the exact expected shape; the
non-English canary rejects English-identical values, so each needs a real
translation. Keep the `requiredKeys` list alphabetically consistent with the
existing block.

#### 5. New tests
**Files**: `CheckStitchTests/ChecklistStoreTests.swift`, `CheckStitchTests/CheckListListViewModelTests.swift`
**Action**: modify

- store `testRenameFolderPersistsAndDisambiguates` — rename to an existing sibling name → `"<name> 2"`; reload matches; revision bumped once.
- store `testRenameFolderToItsOwnNameIsANoOp` — same name (and trimmed variant) leaves revision unchanged.
- store `testMoveFoldersReordersAndPersists` — `moveFolders(from: IndexSet(integer: 1), to: 0)`; reload matches; no revision bump on either folder.
- store `testMoveFoldersOutOfRangeIsANoOp`.
- VM `moveFolderUpReordersFolders` / `moveFolderDownReordersFolders`.
- VM `renameFolderReflects`.

### Verification
#### Automated
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make test-unit` passes (incl. `LocalizationTests.everyRequiredKeyIsPresent`)
- [x] `make build` passes

#### Manual
- [ ] `make run`: edit mode → a folder header shows pencil + up/down; rename opens the alert pre-filled; renaming to an existing name yields a " 2" suffix; chevrons reorder; relaunch preserves order
- [ ] Non-edit mode shows no folder controls

---

## Phase 4: Delete a folder, orphaning its checklists

### Changes

#### 1. Store delete
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

```swift
/// Deletes a folder: every member is sent back to loose in the same batch
/// (each member's coarse clock bumps so the orphan wins the LWW round), and one
/// grow-only `FolderTombstone` blocks resurrection. Never writes checklist
/// tombstones — the checklists survive.
func deleteFolder(id: UUID) {
    guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
    let removed = folders.remove(at: index)
    let deletedAt = now()
    for checklistIndex in checklists.indices where checklists[checklistIndex].folderID == id {
        checklists[checklistIndex].folderID = nil
        checklists[checklistIndex].revision += 1
        checklists[checklistIndex].modifiedAt = deletedAt
    }
    folderTombstones.append(FolderTombstone(folderID: id, deletedAt: deletedAt, revision: removed.revision + 1))
    save()
}
```
One `save()` for the whole batch; a folder with no members writes only the tombstone.

#### 2. View model
**File**: `CheckStitch/ChecklistListViewModel.swift`
**Action**: modify

```swift
/// The folder waiting for its confirm/cancel in the delete dialog; `nil` hides it.
var folderPendingRemoval: UUID?

func removeFolder(id: UUID) {
    store.deleteFolder(id: id)
}
```

#### 3. Main screen: staged delete dialog
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add a minus control first in `folderEditControls`:
```swift
Button { listVM.folderPendingRemoval = folder.id } label: {
    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
}
.buttonStyle(.plain)
.accessibilityLabel("Remove Folder")
.accessibilityIdentifier("removeFolder-\(folder.id.uuidString)")
```

Staged `confirmationDialog` beside the existing checklist one:
```swift
.confirmationDialog(
    "Delete Folder",
    isPresented: Binding(get: { listVM.folderPendingRemoval != nil },
                         set: { if !$0 { listVM.folderPendingRemoval = nil } }),
    presenting: listVM.folderPendingRemoval
) { id in
    Button("Delete", role: .destructive) {
        listVM.folderPendingRemoval = nil
        withAnimation { listVM.removeFolder(id: id) }
    }
    .accessibilityIdentifier("confirmRemoveFolderButton")
    Button("Cancel", role: .cancel) { listVM.folderPendingRemoval = nil }
        .accessibilityIdentifier("cancelRemoveFolderButton")
} message: { _ in
    Text("This removes the folder. Its checklists become loose.")
}
```

#### 4. Localization keys
**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add `"Delete Folder"` and `"This removes the folder. Its checklists become loose."`
(all six languages) + `requiredKeys` entries. Reuse the existing `"Cancel"`,
`"Done"`, `"Delete"`? — `"Delete"` is NOT currently required; add it or reuse
`"Remove"` for the destructive label. Prefer adding `"Delete"` with all six
languages (check whether it already exists in the catalog before adding).

#### 5. New tests
**Files**: `CheckStitchTests/ChecklistStoreTests.swift`, `CheckStitchTests/ChecklistMergeTests.swift`
**Action**: modify

- store `testDeleteFolderOrphansMembersAndPersistsTombstone` — folder + 2 members; delete → `folders == []`, both members `folderID == nil` with revision bumped, `folderTombstones` has one record with `revision == removed.revision + 1`; reload preserves all of it.
- store `testDeleteEmptyFolderWritesOnlyTheTombstone` — no members → one tombstone, `checklists` untouched.
- store `testDeleteUnknownFolderIsANoOp`.
- merge `folderTombstoneRemovesTheFolderButKeepsItsChecklists` — after merge the folder is gone, the member checklist remains (Phase 2's version asserted the tombstone; this asserts the orphan survives and is not given a checklist tombstone).

### Verification
#### Automated
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make test-unit` passes
- [x] `make build` passes

#### Manual
- [ ] `make run`: edit a folder → minus → confirm dialog → folder disappears and its checklists appear under "Loose"; relaunch preserves it
- [ ] Cancelling the dialog leaves the folder intact

---

## Phase 5: Watch shows folders as sections

### Changes

#### 1. Core read-only grouping surface
**File**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
**Action**: modify

Append the grouping types to the one model file (string-free — no new Core
localization keys):
```swift
/// One rendered group on the list screens. `folder == nil` is the loose group.
public struct ChecklistSection: Identifiable, Equatable, Sendable {
    public init(folder: Folder?, checklists: [Checklist]) {
        self.folder = folder
        self.checklists = checklists
    }

    public let folder: Folder?
    public let checklists: [Checklist]
    public var id: String { folder?.id.uuidString ?? "loose" }
    public var name: String? { folder?.name }
}

/// Read-only grouping used by the watch (and any surface that needs sections).
public enum ChecklistGrouping {
    /// Folders in persisted order, each followed by its members in global
    /// checklist order; then the loose section last. A `folderID` naming an
    /// unknown folder is grouped loose, so cross-reference skew never drops a
    /// checklist.
    public static func sections(folders: [Folder], checklists: [Checklist]) -> [ChecklistSection] {
        let known = Set(folders.map(\.id))
        var byFolder: [UUID: [Checklist]] = [:]
        var loose: [Checklist] = []
        for checklist in checklists {
            if let folderID = checklist.folderID, known.contains(folderID) {
                byFolder[folderID, default: []].append(checklist)
            } else {
                loose.append(checklist)
            }
        }
        var sections = folders.map { ChecklistSection(folder: $0, checklists: byFolder[$0.id] ?? []) }
        sections.append(ChecklistSection(folder: nil, checklists: loose))
        return sections
    }
}
```

#### 2. Phone→watch transport carries folders
**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`, `CheckStitch/MyApp.swift`
**Action**: modify

Coordinator: add a defaulted closure so existing call sites compile:
```swift
public init(
    transport: ChecklistSyncTransport,
    snapshot: @escaping () -> [Checklist],
    folders: @escaping () -> [Folder] = { [] },
    createReminders: @escaping (Checklist) async -> ReminderRunOutcome,
    language: @escaping @MainActor () -> AppLanguage
) { ... self.folders = folders ... }

private let folders: () -> [Folder]
```
and include them in `pushContext`:
```swift
let envelope = ChecklistEnvelope(version: ChecklistCodec.currentVersion, deviceID: "",
                                 checklists: snapshot(), folders: folders())
```

`MyApp.swift`:
```swift
snapshot: { store.checklists },
folders: { store.folders },
```
and push on folder changes (folder edits do not touch `store.checklists`):
```swift
.onChange(of: store.folders) { _, _ in coordinator?.checklistsDidChange() }
```

#### 3. Watch store receives folders
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift`
**Action**: modify

`WatchChecklistStore` gains `public private(set) var folders: [Folder] = []`, and
`receive(_:)`'s `.context` branch sets both from the envelope:
```swift
case .loaded(let envelope):
    checklists = envelope.checklists
    folders = envelope.folders
case .migratable(let from, let envelope) where from >= 2:
    checklists = envelope.checklists
    folders = envelope.folders
```

#### 4. Watch view model + list
**Files**: `CheckStitchWatch/WatchChecklistViewModel.swift`, `CheckStitchWatch/WatchChecklistListView.swift`
**Action**: modify

```swift
var folders: [Folder] { store.folders }

var sections: [ChecklistSection] {
    ChecklistGrouping.sections(folders: store.folders, checklists: store.checklists)
}
```

`WatchChecklistListView`:
```swift
List {
    ForEach(viewModel.sections) { section in
        Section {
            ForEach(section.checklists) { checklist in
                NavigationLink(checklist.name) {
                    WatchChecklistDetailView(checklist: checklist)
                }
            }
        } header: {
            // Keep the flat (no-folder) watch list exactly as it was; label the
            // loose section only once folders exist.
            if section.folder != nil {
                Text(section.name ?? "")
            } else if viewModel.sections.count > 1 {
                Text("Loose")
            }
        }
    }
}
```

#### 5. Watch localization key
**Files**: `CheckStitchWatch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

Add `"Loose"` to the Watch catalog (all six languages) and to the `"Watch"`
`requiredKeys` list. Core catalog unchanged (grouping has no strings); state this
in the completion artifact.

#### 6. New tests
**Files**: `CheckStitchTests/ChecklistGroupingTests.swift` (new), `CheckStitchTests/WatchChecklistStoreTests.swift`, `CheckStitchTests/ChecklistSyncCoordinatorTests.swift`
**Action**: create / modify

`ChecklistGroupingTests` (new file, Swift Testing; no `project.pbxproj` edit needed):
- `membersFollowGlobalOrder` — folder members preserve global array order.
- `looseSectionIsLast` — sections end with the `folder == nil` entry.
- `unknownFolderIDFallsIntoLoose` — a `folderID` with no matching folder lands in loose, not dropped.
- `emptyFolderProducesAnEmptySection` — a folder with no members yields a section with `checklists == []`.

`WatchChecklistStoreTests`:
- `contextCarriesFoldersToTheWatch` — deliver an envelope with a folder + a member checklist; `store.folders == [folder]`, `store.checklists` unchanged.

`ChecklistSyncCoordinatorTests`:
- extend `makeCoordinator` with a `folders: [Folder] = []` parameter passed through;
- `startPushesFoldersInTheContext` — decode `transport.sentContexts[0]`, assert `folders == [folder]`.

### Verification
#### Automated
- [x] `make test-unit` passes
- [x] `make watch-build` passes
- [x] `make build` passes
- [x] `bash scripts/l10n-check.sh` passes (including the Watch key)

#### Manual
- [ ] `bash scripts/run-watch.sh` (with the phone app running): the watch list shows the same folder names as sections and the loose group last; tapping a checklist still opens its detail view
- [ ] Renaming/reordering a folder on the phone updates the watch after the next context push

---

## Phase 6: Hardening, states, and localization

### Changes

#### 1. Cross-reference skew + empty states
**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`, `CheckStitch/ChecklistListViewModel.swift`, `CheckStitch/ContentView.swift`
**Action**: modify (fallbacks already implemented; this phase verifies and closes gaps)

- Confirm `ChecklistGrouping.sections` and `ChecklistListViewModel.checklists(in: nil)` both route an unknown `folderID` to loose (already written in Phases 1/5).
- Confirm an empty-folder section renders a header with no rows and that no divider doubles up when the loose group is empty.
- Add the Phase-1 `folderEditControls` call to `folderHeader` if it was deferred; ensure nothing renders in non-edit mode.

#### 2. Localization sweep
**Files**: `CheckStitch/Localizable.xcstrings`, `CheckStitchWatch/Localizable.xcstrings`, `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`, `CheckStitchTests/LocalizationTests.swift`
**Action**: modify only as needed

- Assert every key introduced in Phases 1/3/4/5 is present in its catalog with all six languages and in the matching `requiredKeys` list. The Core catalog is expected to be unchanged — if `LocalizationTests`/`l10n-check.sh` pass without touching it, record that.
- Any non-English value that trips the canary must be a real translation, not an `excludedIdentities` exemption unless the term is genuinely locale-invariant.
- `LocalizationTests.swift` itself needs no change (the suites are data-driven).

#### 3. UI smoke
**File**: `CheckStitchUITests/CheckStitchUITests.swift`
**Action**: modify only if it fails

Run `make test-ui`. The smoke test does not enter edit mode, so its identifiers
(`createChecklistButton`, `settingsButton`, `emptyStateCreateButton` /
`createRemindersButton`, `settingsButton`) should still resolve. If the
accessibility audit flags a new element, fix the offending view's label rather
than weakening the audit.

#### 4. New tests
**Files**: `CheckStitchTests/CheckListListViewModelTests.swift`, `CheckStitchTests/ChecklistGroupingTests.swift`
**Action**: modify

- VM `unknownFolderIsRenderedAsLoose` — a checklist whose `folderID` names no folder appears in `checklists(in: nil)` and not in any folder section.
- Grouping `emptyFolderWithLooseMembersRendersLooseLast` (if not already covered).

### Verification
#### Automated
- [x] `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] `make test-unit` passes
- [x] `make test-ui` passes
- [ ] `bash scripts/test.sh` prints `gate: ok` (runs `make build`, sim pre-boot, `make test`, `make build-mac`, `make watch-build`, `bash scripts/tests/run.sh`, `shellcheck`)
- [ ] `make build-mac-signed` passes (provisioning leg the gate does not cover)

#### Manual
- [ ] `make run`: create folders, move checklists in/out, rename, reorder, delete — all persist across relaunch; an empty folder and an all-loose list render cleanly
- [ ] Real-device close-out (required for sync/UI tickets): `bash scripts/run-devices.sh` → the installed app shows folder sections on iPhone + host Mac, and moving/renaming/deleting a folder syncs to the second device and the paired watch; state what the user should see (folder header, members indented, "Loose" group)
- [ ] Watch: `bash scripts/run-watch.sh` shows the same sections

---

## Testing Checkpoints

- After Phase 1: `make test-unit` + `make build` green → model/envelope/membership contract frozen (v5 bump, v4 defaults, additive `folderID`).
- After Phase 2: merge tests green incl. idempotence → sync risk retired.
- After Phase 3: rename/reorder tests green → folder management contract frozen.
- After Phase 4: orphan + tombstone tests green → destructive path safe.
- After Phase 5: `make watch-build` green, grouping + transport tests green → watch consumes core only.
- After Phase 6: `bash scripts/test.sh` → `gate: ok`; real-device close-out done.

## Files touched (complete)

| File | Phases |
| --- | --- |
| `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` | 1, 5, 6 |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift` | 5 |
| `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift` | 5 |
| `CheckStitch/ChecklistStore.swift` | 1, 3, 4 |
| `CheckStitch/ChecklistMerge.swift` | 1 (test-gated 2) |
| `CheckStitch/ChecklistListViewModel.swift` | 1, 3, 4, 6 |
| `CheckStitch/ChecklistSyncService.swift` | 1 |
| `CheckStitch/ContentView.swift` | 1, 3, 4, 6 |
| `CheckStitch/MyApp.swift` | 5 |
| `CheckStitchWatch/WatchChecklistViewModel.swift` | 5 |
| `CheckStitchWatch/WatchChecklistListView.swift` | 5 |
| `CheckStitch/Localizable.xcstrings` | 1/3/4/6 |
| `CheckStitchWatch/Localizable.xcstrings` | 5/6 |
| `CheckStitchCore/.../Resources/Localizable.xcstrings` | 6 (verify unchanged) |
| `CheckStitchTests/ChecklistCodecTests.swift` | 1 |
| `CheckStitchTests/ChecklistStoreTests.swift` | 1, 3, 4 |
| `CheckStitchTests/CheckListListViewModelTests.swift` | 1, 3, 6 |
| `CheckStitchTests/ChecklistMergeTests.swift` | 2, 4 |
| `CheckStitchTests/ChecklistGroupingTests.swift` | 5, 6 (new) |
| `CheckStitchTests/WatchChecklistStoreTests.swift` | 5 |
| `CheckStitchTests/ChecklistSyncCoordinatorTests.swift` | 5 |
| `CheckStitchTests/LocalizationFixtures.swift` | 1/3/4/5/6 |
| `CheckStitchTests/LocalizationTests.swift` | 6 (data-driven; likely unchanged) |
| `CheckStitchUITests/CheckStitchUITests.swift` | 6 (only if smoke fails) |

No `project.pbxproj` edit: all new files live under synchronized folder groups.