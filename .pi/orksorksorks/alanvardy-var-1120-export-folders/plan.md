# Implementation Plan

## Overview

Make folder membership survive export/reimport: export writes the folders referenced by the
selected checklists (deduped, empty `folderTombstones`, `deviceID: ""`), and import resolves each
file folder **by name** against local folders — creating missing ones — then reparents the imported
checklists through a folder-aware store write. No schema/version change: the v5 envelope already
carries `folders`/`folderTombstones`.

## Deviations from `structure.md` (deliberate, noted once here)

1. **`ChecklistExportDocument` gains `from folders:`** and its call sites
   (`ChecklistImportExportViewModel`, `ChecklistExportTests`, `ChecklistShareTests`) are updated.
   Structure listed the view model but not the `FileDocument` wrapper between it and
   `ChecklistExport`; the wrapper must forward folders or the view model cannot.
2. **`ChecklistExport.data`/`envelope` have no folder default** (per design), so every existing
   test call site using `ChecklistExport.data(checklists:)` is mechanically updated to
   `from: []`. Exact list in Phase 1.
3. **`commit` builds `folderMap` for the folders referenced by *selected* candidates only** (not
   every `envelope.folders`). Resolving unticked checklists' folders would create folders the user
   did not ask to import. The shape (map first, then insert) is otherwise structure's.
4. **`resolveOrCreateFolder` grows an `isCollapsed` parameter in Phase 3** (`= false` default keeps
   Phase 1/2 call sites green); Phase 3 flips the session helper to pass the file value.
5. **Blank file-folder name falls back to `"New Folder"`**, mirroring `createFolder`, so a
   hand-edited blank name cannot mint a nameless folder.

---

## Phase 1: Walking skeleton — export/reimport reconstructs folder membership end to end

### Changes

#### 1. `ChecklistExport` carries referenced folders
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift`
**Action**: modify

Replace the docstring's "no tombstones" wording with "no tombstones and no foreign device id" and
make folders explicit on both entry points. **No default argument** — the implicit `[]` default is
the bug.

```swift
public static func envelope(checklists: [Checklist], from folders: [Folder]) -> ChecklistEnvelope {
    let referenced = Set(checklists.compactMap(\.folderID))
    return ChecklistEnvelope(version: ChecklistCodec.currentVersion,
                             deviceID: "",
                             checklists: checklists,
                             tombstones: [],
                             folders: folders.filter { referenced.contains($0.id) },
                             folderTombstones: [])
}

public static func data(checklists: [Checklist], from folders: [Folder]) throws -> Data {
    try ChecklistCodec.encode(envelope(checklists: checklists, from: folders))
}
```

`filename(for:calendar:)` is unchanged.

#### 2. `ChecklistExportDocument` forwards folders
**File**: `CheckStitch/ChecklistExportDocument.swift`
**Action**: modify

```swift
init(checklists: [Checklist], from folders: [Folder]) throws {
    self.data = try ChecklistExport.data(checklists: checklists, from: folders)
}
```

#### 3. View model passes `store.folders`
**File**: `CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: modify

In `exportSelected()` and `shareSelected()`, replace `ChecklistExportDocument(checklists: selected)`
with:

```swift
exportDocument = try ChecklistExportDocument(checklists: selected, from: store.folders)
// and in shareSelected:
pendingShare = try ChecklistExportDocument(checklists: selected, from: store.folders)
```

#### 4. Store: folder-aware write path
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

- `freshCopy(of:)` gains a folder parameter (default preserves Phase-1 `importReplace`'s today's
  drop-folder behavior; `duplicate` does **not** call `freshCopy`, so it is untouched):

```swift
private func freshCopy(of checklist: Checklist, folderID: UUID? = nil) -> Checklist {
    Checklist(
        name: checklist.name,
        items: checklist.items.map {
            ChecklistItem(title: $0.title, description: $0.description,
                          modifiedAt: now(), revision: 1, relativeDate: $0.relativeDate,
                          priority: $0.priority)
        },
        destinationListIdentifier: checklist.destinationListIdentifier,
        prefixesReminderNumbers: checklist.prefixesReminderNumbers,
        showsOnWatch: checklist.showsOnWatch,
        multiple: checklist.multiple,
        folderID: folderID,
        isArchived: false,
        archivedAt: nil,
        modifiedAt: now(),
        revision: 1
    )
}
```

- `importInsert` gains `folderID` and forwards it (all existing callers keep compiling via the
  default):

```swift
@discardableResult
public func importInsert(_ checklist: Checklist, as name: String? = nil, folderID: UUID? = nil) -> UUID {
    var copy = freshCopy(of: checklist, folderID: folderID)
    copy.name = name ?? Self.uniqueName(basedOn: copy.name, taken: activeNames)
    checklists.append(copy)
    save()
    return copy.id
}
```

- Add `resolveOrCreateFolder(named:)` directly after `createFolder(name:)`. It mints **in memory**
  and deliberately does not `save()`; the caller's `importInsert`/`importReplace` supplies the
  single save.

```swift
/// Resolves a file folder name to a local folder: an existing folder whose name
/// matches (`sameName`: trimmed, case-insensitive) is reused; otherwise a fresh
/// folder is minted in memory with a `uniqueName`-disambiguated name. Does NOT
/// `save()` — the caller's checklist write shares the single save.
@discardableResult
public func resolveOrCreateFolder(named rawName: String) -> UUID {
    let requested = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    if let existing = folders.first(where: { Self.sameName($0.name, requested) }) {
        return existing.id
    }
    let name = Self.uniqueName(basedOn: requested.isEmpty ? "New Folder" : requested,
                               taken: folders.map(\.name))
    let folder = Folder(name: name, modifiedAt: now(), revision: 1)
    folders.append(folder)
    return folder.id
}
```

#### 5. Import session: decode envelope, stash file folders, folder-aware commit
**File**: `CheckStitch/ChecklistImportSession.swift`
**Action**: modify

- Add `private var fileFolders: [Folder] = []`.
- `stage`: receive an envelope, stash its folders, map its checklists.

```swift
@discardableResult
func stage(data: Data) throws -> [ChecklistImportCandidate] {
    pending = []
    summary = ImportSummary()
    candidates = []
    let envelope = try decoded(data)
    fileFolders = envelope.folders
    candidates = envelope.checklists.map { checklist in
        ChecklistImportCandidate(
            id: checklist.id,
            checklist: checklist,
            conflicting: store.conflictingChecklist(named: checklist.name))
    }
    return candidates
}
```

- `decoded(_:)` returns `ChecklistEnvelope` (migratable branch rebuilds an envelope so
  folders/tombstones ride through):

```swift
private func decoded(_ data: Data) throws -> ChecklistEnvelope {
    switch ChecklistCodec.classify(data) {
    case .loaded(let envelope):
        return envelope
    case .migratable(let from, let envelope):
        let migrated = envelope.checklists.map { checklist in
            switch from {
            case 1: return checklist.migrated(at: now())
            case 2: return checklist.seededOrder()
            default: return checklist
            }
        }
        return ChecklistEnvelope(version: envelope.version,
                                 deviceID: envelope.deviceID,
                                 checklists: migrated,
                                 tombstones: envelope.tombstones,
                                 folders: envelope.folders,
                                 folderTombstones: envelope.folderTombstones)
    case .unsupportedVersion:
        throw ChecklistImportError.unsupportedVersion
    case .unreadable:
        throw ChecklistImportError.unreadable
    }
}
```

- Add the private resolution helper (commit-time; `stage` stays write-free):

```swift
/// File-folder id -> local folder id, minting a matching local folder when the
/// file folder is known. `nil` for an absent/nil file folder id (orphan) — the
/// checklist lands loose.
private func localFolderID(forFileFolderID fileFolderID: UUID?) -> UUID? {
    guard let fileFolderID,
          let fileFolder = fileFolders.first(where: { $0.id == fileFolderID })
    else { return nil }
    return store.resolveOrCreateFolder(named: fileFolder.name)
}
```

- `commit`: build `folderMap` for the folders referenced by selected candidates, then insert with
  the resolved folder.

```swift
@discardableResult
func commit(selectedIDs: Set<UUID>) -> ImportSummary {
    var result = ImportSummary()
    let selected = candidates.filter { selectedIDs.contains($0.id) }
    var folderMap: [UUID: UUID] = [:]
    for candidate in selected {
        guard let fileFolderID = candidate.checklist.folderID,
              folderMap[fileFolderID] == nil,
              let localID = localFolderID(forFileFolderID: fileFolderID)
        else { continue }
        folderMap[fileFolderID] = localID
    }
    for candidate in selected {
        if let conflict = store.conflictingChecklist(named: candidate.checklist.name) {
            pending.append(ChecklistImportCandidate(
                id: candidate.id, checklist: candidate.checklist, conflicting: conflict))
        } else {
            store.importInsert(candidate.checklist,
                               folderID: candidate.checklist.folderID.flatMap { folderMap[$0] })
            result.inserted += 1
        }
    }
    summary = result
    return result
}
```

#### 6. Test call-site migration + new suites
**Files**: `CheckStitchTests/ChecklistExportTests.swift`,
`CheckStitchTests/ChecklistShareTests.swift`,
`CheckStitchTests/ChecklistImportExportViewModelTests.swift`,
`CheckStitchTests/ChecklistImportSessionTests.swift`,
`CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

Mechanical signature migration (add `from: []` / `from: folders`):

- `ChecklistExportTests.swift` lines 25, 49, 71, 91, 103, 118, 130: `ChecklistExport.data(checklists: X)` →
  `try ChecklistExport.data(checklists: X, from: [])`. Line 158:
  `ChecklistExportDocument(checklists: selected)` → `(checklists: selected, from: [])`.
- `ChecklistShareTests.swift` line 11: `ChecklistExportDocument(checklists: checklists)` →
  `(checklists: checklists, from: [])`; line 51: `(checklists: [], from: [])`.
- `ChecklistImportExportViewModelTests.swift` lines 80, 97, 114, 128, 214, 215, 228: add `from: []`.

`ChecklistImportSessionTests.swift` `payload` helper gains folders/tombstones (existing calls stay
valid):

```swift
private func payload(_ checklists: [Checklist],
                     folders: [Folder] = [],
                     folderTombstones: [FolderTombstone] = [],
                     version: Int = ChecklistCodec.currentVersion) throws -> Data {
    try ChecklistCodec.encode(ChecklistEnvelope(version: version, deviceID: "",
                                                checklists: checklists,
                                                folders: folders,
                                                folderTombstones: folderTombstones))
}
```

New tests (names + intent; @MainActor on all as today):

**`ChecklistExportTests` (XCTest)**
- `testExportCarriesReferencedFoldersDedupedAndShipsNoTombstones` — build folder `Groceries`,
  member checklists A/B (same `folderID`), an unreferenced folder, and one loose checklist; export
  `selected` + `folders: allFolders`; assert `env.folders.map(\.name) == ["Groceries"]`,
  `env.folderTombstones.isEmpty`, `env.tombstones.isEmpty`, `env.deviceID == ""`.
- `testExportOmitsFoldersWhenSelectionHasNone` — loose selection → `env.folders.isEmpty`.

**`ChecklistStoreTests` (XCTest, isolated defaults + reload pattern)**
- `testResolveOrCreateFolderReusesSameName` — `createFolder(name: "Work")`; resolve `" work "`;
  same id, `folders.count == 1`.
- `testResolveOrCreateFolderMintsWhenAbsent` — resolve `"Work"` on empty store; `folders.map(\.name)
  == ["Work"]`, revision 1.
- `testImportInsertWithFolderCarriesMembership` — folder; `importInsert(checklist, folderID:
  folder.id)`; `store.checklist(id:)?.folderID == folder.id`; reload → still member.
- `testImportInsertWithoutFolderLandsLoose` — `importInsert(checklist)`; `folderID == nil` (guards
  the default).

**`ChecklistImportSessionTests` (Swift Testing)**
- `exportedFolderIsRecreatedWhenImportingIntoEmptyStore` — source store: `createFolder(name:
  "Groceries")`, member checklist; `ChecklistExport.data(checklists: [member], from:
  store.folders)`; fresh empty store session: stage+commit → `store.folders.map(\.name) ==
  ["Groceries"]`, imported `folderID == store.folders.first?.id`.
- `reImportingTheSameFileDoesNotDuplicateFolder` — same payload committed twice into one store →
  `folders.count == 1`, both member checklists point at one folder (names `base`/`base 2`).
- `stagingAFolderBearingFileWritesNothing` — after `stage`, `store.folders.isEmpty` and
  `store.checklists.isEmpty`.

**`ChecklistImportExportViewModelTests` (Swift Testing)**
- `exportSelectedWritesAFolderBearingPayload` — store: folder + member; `beginExport`,
  `exportSelection = [member.id]`, `exportSelected()`; `ChecklistCodec.classify(
  viewModel.exportDocument!.data)` → `.loaded(env)`, `env.folders.map(\.name) == ["Groceries"]`.
- `shareSelectedRecordsAFolderBearingPayload` — same via `pendingShare`.

### Verification
#### Automated
- [x] `make test-unit` passes (new folder suites green, migrated call sites compile).
- [x] `make build` passes (Document/view-model signature change compiles in the app target;
      warnings-as-errors).
#### Manual
- [ ] Simulator (`make run`): create a folder "Groceries", move a checklist into it, select that
      checklist, Export → open the JSON and confirm `"folders"` contains "Groceries" and
      `"folderTombstones"` is `[]`.

---

## Phase 2: Conflict decisions carry folder membership

### Changes

#### 1. `importReplace` is folder-aware
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

```swift
@discardableResult
public func importReplace(id: UUID, with checklist: Checklist, folderID: UUID? = nil) -> UUID? {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return nil }
    let removed = checklists.remove(at: index)
    tombstones.append(ChecklistTombstone(
        checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
    let copy = freshCopy(of: checklist, folderID: folderID)
    checklists.append(copy)
    save()
    return copy.id
}
```

#### 2. `decide` forwards the resolved folder
**File**: `CheckStitch/ChecklistImportSession.swift`
**Action**: modify

```swift
case .replace:
    if let conflict = candidate.conflicting,
       store.importReplace(id: conflict.id, with: candidate.checklist,
                           folderID: localFolderID(forFileFolderID: candidate.checklist.folderID)) != nil {
        summary.replaced += 1
    }
case .keepBoth:
    store.importInsert(candidate.checklist,
                       folderID: localFolderID(forFileFolderID: candidate.checklist.folderID))
    summary.keptBoth += 1
case .keepExisting:
    summary.keptExisting += 1
```

`.keepExisting` still branches earlier and writes nothing.

#### 3. Tests
**File**: `CheckStitchTests/ChecklistImportSessionTests.swift`
**Action**: modify

- `replaceReparentsTheSurvivorIntoTheImportedFolder` — local "Groceries" loose; file payload has
  folder "Work" + conflicting "Groceries"; commit → decide `.replace`; surviving checklist is in
  the local "Work" folder.
- `replaceWithUnresolvedFileFolderLandsLoose` — conflicting checklist whose file `folderID` names no
  folder in the payload; `.replace` → survivor `folderID == nil`.
- `keepBothCopyLandsInTheImportedFolder` — conflict + file folder; `.keepBoth` → imported copy's
  `folderID` is the local folder; local original unchanged.
- `keepExistingLeavesLocalFoldersUntouched` — local has folder "Home" + local member; file conflict
  into folder "Work"; `.keepExisting` → `store.folders.map(\.name) == ["Home"]`, local member
  unchanged.

### Verification
#### Automated
- [x] `make test-unit` passes (folder behaviour for `.replace`/`.keepBoth`/`.keepExisting`).
#### Manual
- [ ] None beyond Phase 1.

---

## Phase 3: Hardening — orphans, collapse state, ignored tombstones, collisions

### Changes

#### 1. `resolveOrCreateFolder` adopts `isCollapsed` on create
**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
**Action**: modify

```swift
@discardableResult
public func resolveOrCreateFolder(named rawName: String, isCollapsed: Bool = false) -> UUID {
    let requested = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    if let existing = folders.first(where: { Self.sameName($0.name, requested) }) {
        return existing.id          // reuse keeps the local folder's own isCollapsed
    }
    let name = Self.uniqueName(basedOn: requested.isEmpty ? "New Folder" : requested,
                               taken: folders.map(\.name))
    let folder = Folder(name: name, isCollapsed: isCollapsed, modifiedAt: now(), revision: 1)
    folders.append(folder)
    return folder.id
}
```

#### 2. Session helper passes the file collapse value
**File**: `CheckStitch/ChecklistImportSession.swift`
**Action**: modify

```swift
return store.resolveOrCreateFolder(named: fileFolder.name, isCollapsed: fileFolder.isCollapsed)
```

No other session change: orphan `folderID` already resolves to `nil` via the helper's `guard let` +
`first(where:)`; the file's `folderTombstones` are never read (only `envelope.folders` is stashed);
duplicate-named file folders collapse because the second `resolveOrCreateFolder` hits `sameName` on
the first-minted folder, both in one commit's `folderMap`.

#### 3. Tests
**Files**: `CheckStitchTests/ChecklistImportSessionTests.swift`,
`CheckStitchTests/ChecklistExportTests.swift`
**Action**: modify

**`ChecklistImportSessionTests`**
- `checklistWithOrphanFolderIDLandsLoose` — payload has a checklist with `folderID` set but no
  matching entry in `folders`; commit → `folderID == nil`, `store.folders.isEmpty`, no crash.
- `importedCollapseStateIsAdoptedOnFolderCreate` — payload folder `Folder(name: "Work",
  isCollapsed: true)`; import into empty store → local folder's `isCollapsed == true`.
- `existingFolderKeepsItsLocalCollapseState` — local `Folder(name: "Work", isCollapsed: false)`
  (via `createFolder`), payload same name `isCollapsed: true`; import → local stays `false`,
  `folders.count == 1`.
- `fileFolderTombstoneIsIgnored` — local has folder "Work"; payload carries folder "Work", an
  unrelated checklist, and a `folderTombstones: [FolderTombstone(folderID: fileWorkFolder.id,
  deletedAt: .now(), revision: 9)]` entry; import → local "Work" survives.
- `twoSameNamedFoldersInOneFileCollapseToOne` — payload `[Folder(name: "Work"), Folder(name:
  "Work")]` with a checklist in each; import → `store.folders.map(\.name) == ["Work"]`, both
  checklists share that folder id.
- `renamedLocalFolderGetsANewFolderOnImport` — local folder "Food"; payload folder "Groceries";
  import → `store.folders.map(\.name) == ["Food", "Groceries"]` (documented consequence).

**`ChecklistExportTests`**
- `testExportFolderInvariants` — one checklist in a folder: `env.folders.count == 1`,
  `env.folderTombstones.isEmpty`, `env.tombstones.isEmpty`, `env.deviceID == ""` (regression pin
  for the trio; do not duplicate the dedup assertion from Phase 1).

### Verification
#### Automated
- [x] `make test-unit` passes.
- [x] `./scripts/test.sh` prints `gate: ok` (simulator build → pre-boot → `make test` →
      `build-mac` → `watch-build` → `scripts/tests/run.sh` → `shellcheck`; warnings-as-errors).
#### Manual
- [ ] Optional: on a fresh simulator install, import a folder-bearing export → the imported
      checklist appears under a folder of the same name; import the same file again → still one
      folder.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` green — round trip into an empty store and re-import idempotency.
- After Phase 2: `make test-unit` green — `.replace`/`.keepBoth`/`.keepExisting` folder behavior.
- After Phase 3: `./scripts/test.sh` prints `gate: ok`.

## Files touched (complete)

- `CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift`
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`
- `CheckStitch/ChecklistExportDocument.swift`
- `CheckStitch/ChecklistImportSession.swift`
- `CheckStitch/ChecklistImportExportViewModel.swift`
- `CheckStitchTests/ChecklistExportTests.swift`
- `CheckStitchTests/ChecklistImportSessionTests.swift`
- `CheckStitchTests/ChecklistImportExportViewModelTests.swift`
- `CheckStitchTests/ChecklistStoreTests.swift`
- `CheckStitchTests/ChecklistShareTests.swift` (call-site migration only)

No `Localizable.xcstrings` changes (UI is silent), no schema/version change, no
`ChecklistMerge`/`ChecklistSyncCoordinator`/Watch changes.
