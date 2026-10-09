# Research Findings

## Q1: Export envelope construction and payload

### Findings
- `ChecklistExport.envelope(checklists:)` builds
  `ChecklistEnvelope(version: currentVersion, deviceID: "", checklists: checklists, tombstones: [])`
  (`ChecklistExport.swift:8-12`). The header docstring states the intent: "version current,
  no device identity, no tombstones … never resurrects deletions or injects a foreign deviceID
  into a future LWW tie-break" (`:3-6`).
- `folders` and `folderTombstones` are **defaulted to `[]`** by the envelope init
  (`Checklist.swift:517-519`) and never overridden on export, so an export payload always
  serializes both as empty arrays. This is the only producer that omits folders —
  `ChecklistSyncCoordinator.swift:47` passes `folders: folders()`; export does not.
- The `ChecklistEnvelope` has six fields — `version, deviceID, checklists, tombstones,
  folders, folderTombstones` (`Checklist.swift:506-510`) — and its custom `encode` writes all
  six (`:574-587`), so empty values are written explicitly, not omitted.
- **Field-by-field payload:** `version` = `currentVersion` (5) `Checklist.swift:564`;

  `deviceID` = `""` (`ChecklistExport.swift:9`); `checklists` = user selection;
  `tombstones` = `[]` (`:10`); `folders` = `[]` (default); `folderTombstones` = `[]` (default).
- **Selection:** `exportSelected()` filters `store.activeChecklists` by `exportSelection`
  (`ChecklistImportExportViewModel.swift:56-63`); empty selection → no-op. `shareSelected()`
  (:69-78) does the identical filter but stores a pending share. `ContentView.swift:193-205` wires
  `onExport`/`onShare`; `presentPendingShare()` (:194) flips `isSharing`.
- **Encode/naming:** `ChecklistExport.data` → `ChecklistCodec.encode` = plain
  `JSONEncoder().encode(envelope)` (`Checklist.swift:585-587`). `ChecklistExportDocument` holds
  those bytes (`ChecklistExportDocument.swift:14-16`), `fileWrapper` returns a regular file
  (:24-26), content type `.json` (:12). Exporter: `.fileExporter`, defaultFilename
  `ChecklistExport.filename()` (`ContentView.swift:219-224`). Share (iOS-only): filename
  `ChecklistExport.filename() + ".json"` (`ContentView.swift:237-244`, `#if os(iOS)`).
  `filename` = `"CheckStitch-<yyyy-MM-dd>"` via `en_US_POSIX` DateFormatter (`ChecklistExport.swift:19-27`).

## Q2: Import decode/version and field consumption

### Findings
- `ChecklistImportSession.decoded(_:)` (`ChecklistImportSession.swift:96-104`) is the sole
  decode+migrate entry. `ChecklistCodec.classify(data)` returns **`envelope.checklists` only** on
  `.loaded`/`.migratable`; `.unsupportedVersion`/`.unreadable` throw before any mutation
  (`:21-26`, surfaced in `ChecklistImportExportViewModel.swift:122-128`).
- Version classification (`Checklist.swift`): `currentVersion = 5` (:564); order v5 `.loaded`
  (:599), v4 `.migratable` (predates folders; loaded verbatim :598-601), v3 (predates relativeDate
  :604-606), v2 (ordering seeded :609-611), v1 legacy (:613-614); other → `.unsupportedVersion`
  (:616-617); decode throw → `.unreadable` (:619-621).
- Migration per source version applied in the session: v1 → `checklist.migrated(at: now())`;
  v2 → `checklist.seededOrder()`; v3/v4 → returned unchanged (`ChecklistImportSession.swift:96-104`).
  - `migrated(at:)` (`:356-389`): restamps checklist+item clocks, seeds order. `seededOrder()`
    (:392-400): seeds order without restamping. Decode self-heal normalizes `itemOrder` vs `items`
    (:291-305, `normalizedOrder()` :404-419).
- Envelope decode reads six keys, all `decodeIfPresent`-defaulted: `version`, `deviceID ?? ""`,
  `checklists ?? []`, `tombstones ?? []`, `folders ?? []`, `folderTombstones ?? []`
  (`Checklist.swift:529-541`).
- **Consumed at decoded() stage: only `version` (classification) and `checklists`.**
  `folders`, `folderTombstones`, `tombstones`, `deviceID` load into the envelope but `decoded()`
  never reads them into candidates. `itemOrder` is a per-`Checklist` field (not an envelope field),
  normalized/migrated per checklist before commit.
- **Conflicts/decisions:** `stage` maps each decoded checklist to a `ChecklistImportCandidate`
  and sets `conflicting` via `store.conflictingChecklist(named:)` — read-only probe
  (`ChecklistImportSession.swift:55-69`). `conflictingChecklist` = first *active* checklist name-
  colliding under case-insensitive trimmed `sameName` (`ChecklistStore.swift:200-203`, :420-425).
  `commit(selectedIDs:)` re-checks authoritatively; a now-colliding name → `pending` (FIFO), free →
  `store.importInsert` (:74-88). `decide` drives `ImportDecision {replace, keepBoth, keepExisting}`
  (:124-141): `.replace`→`importReplace`, `.keepBoth`→`importInsert`, `.keepExisting`→count only.
  `importInsert` + `freshCopy` give fresh identity and disambiguate via `uniqueName`
  (`ChecklistStore.swift:298-307`, :273-296, :407-418).

## Q3: Folder / FolderTombstone modeling and serialization

### Findings
- `Checklist.folderID: UUID?` (:238) — "one-field relationship sharing the checklist's coarse
  clock… nil is encoded, never dropped." Optional `CodingKey` (:259); decode
  `decodeIfPresent` → nil for v4-and-earlier (:284); encode writes it **unconditionally**
  (`if let … else encodeNil`, :320-323).
- `Folder: Identifiable, Codable, Hashable, Sendable` (:445) with `id, name, isCollapsed,
  modifiedAt, revision` (:450-456). `isCollapsed` is an additive optional key; absent in
  v5-and-earlier decodes to `false` with no version bump (:457-462, :474). Encode writes all five
  keys unconditionally including `isCollapsed` (:482-486).
- `FolderTombstone` (:490-500): `folderID, deletedAt, revision`, plain synthesized Codable;
  grow-only, suppresses its live folder under merge.
- `ChecklistEnvelope` (:504-560): six fields; `folders`/`folderTombstones` default `[]`
  (:518-519); decode `decodeIfPresent ?? []` (:539-540, legacy v4-and-earlier folderless loads
  verbatim); encode writes both unconditionally (:549-550); equality/include both (:554-555,:559).
- **Single codec channel:** folders serialize on the same v5 envelope payload as checklists — no
  separate folder channel/version. Producers: store persistence (`ChecklistStore.swift:119`),
  sync coordinator (the only producer passing `folders:` explicitly, `ChecklistSyncCoordinator.swift:47`),
  export (`:9`), merge (`ChecklistMerge.swift:38-39`). Folders only carry weight for v5+; pre-v5
  payloads decode folderless and are migrated in place (`Checklist.swift:598-599`).
- `ChecklistGrouping` (read-only, :649-707): `isLoose(_:knownFolderIDs:)` — no folder or unknown
  id → loose (:655-657); `sections(folders:checklists:)` derives from persisted folder order +
  `checklist.folderID`, unknown-folder checklists loose, loose last (:664-677); `visibleFolders`
  derived purely from `checklist.folderID == folder.id` (:701-706).

## Q4: Store write path for imported/duplicated checklists and folder CRUD

### Findings
- `freshCopy(of:)` (`ChecklistStore.swift:274-290`) — the import/duplicate identity mint:
  - **Preserves** name (:275), `destinationListIdentifier` (:283), `prefixesReminderNumbers` (:284),
    `showsOnWatch` (:285), `multiple` (:286); per-item `title, description, relativeDate, priority`
    (:277-281).
  - **Regenerates/drops**: new `ChecklistItem`s (revision 1, now-stamped, no carried UUIDs, :278-279);
    archive reset `isArchived: false, archivedAt: nil` (:281-282); **drops `folderID`**, `itemOrder`,
    and legacy revisions; `modifiedAt: now()`, `revision: 1` (:287-288). New checklist UUID from constructor.
  - Private; consumers are `importInsert`, `importReplace`, and `duplicate` (inline, :245-254).
- `importInsert(_:as:)` (:298-306): `freshCopy`, disambiguate `name` via `uniqueName` against
  `activeNames` unless named, append, one `save()`, return new id. Never re-enters LWW merge.
- `importReplace(id:with:)` (:312-324): guard local exists (:313); remove + append whole-checklist
  `ChecklistTombstone(itemID: nil, revision: removed.revision+1)` (mirrors `delete`, :316-319);
  append fresh copy (:320); single `save()` (:322). Returns `nil` if target vanished.
- `uniqueName` (:407-416, `sameName` :420-424): case-insensitive, whitespace-trimmed; walks
  base→`base 2`…`base 3`; archive names free (`activeNames` :211).
- `save()` (:781-794): cancels debounced save, refuses if `!canOverwriteStoredPayload` (newer-version
  guard :784-787), encodes envelope under key (:788-793), fires `onChange` only when not applying
  remote (:789). `scheduleSave()` coalesces keystrokes over `textEditDelay` (:767-780).
- **Folder CRUD:**
  - `createFolder` :601-607 — trims, defaults `"New Folder"`, `uniqueName` vs folder names,
    `Folder(name:, modifiedAt: now(), revision: 1)`, `save()`.
  - `moveChecklist(id:toFolder:)` :616-630 — guards unknown checklist/folder; no-op on unchanged;
    sets `folderID`, bumps checklist `revision+=1`/`modifiedAt=now()` (this coarse-clock bump is the
    LWW/transfer mechanism through merge).
  - `renameFolder` :631-645, `setFolderCollapsed` :651-658 — share the folder's coarse clock; no-op
    if unchanged.
  - `moveFolders` :664-668 — persists array order, `save()`, no revision stamp (mirrors moveChecklists).
  - `deleteFolder(id:)` :674-687 — removes folder; for members sets `folderID=nil`, `revision+=1`,
    `modifiedAt=deletedAt` so orphans win LWW (no checklist tombstones); appends grow-only
    `FolderTombstone(folderID:, deletedAt:, revision: removed.revision+1)` (:683); single `save()`.
- Net: `freshCopy` carries user intent (name/destination/flags/items) and drops archive + folder +
  itemOrder + legacy revisions. Folder membership lives on `checklist.folderID`; folder deletion
  re-homes members to loose and writes exactly one grow-only tombstone.

## Q5: Sync/merge handling of folders and tombstones

### Findings
- `ChecklistSyncService.reconcileNow()` reads remote bytes, classifies, `store.apply(remote:)`,
  writes back if visible state changed (`ChecklistSyncService.swift:116-165`). Migration copies
  `legacy.folders`/`folderTombstones` for v3 (v1 builds folderless) (:144-150).
- `ChecklistStore.apply(remote:)` → `ChecklistMerge.merge(local:remote:)` (:714-730); on change
  assigns `checklists/tombstones/folders/folderTombstones` from merged envelope.
- `merge` (`ChecklistMerge.swift:14-46`): computes `folderTombstones` (:31), `deadFolders =
  Set(folderTombstones.map(\.folderID))` (:33), then `mergedFolders` (:35) and
  `folders.removeAll { deadFolders.contains($0.id) }` (:36). **Tombstone suppression of live folders
  is unconditional** — folder delete is permanent; recreating mints a new UUID (doc :7-8).
- `mergedFolders` (LWW, :84-104): starts local; remote-only appended; on `wins(revision, modifiedAt,
  device:)` remote wins carrying `name, isCollapsed, revision, modifiedAt` (:94-102). **`isCollapsed`
  rides the folder's single coarse `revision`/`modifiedAt` clock** — carried only on a full folder
  LWW win, not a separate per-field clock.
- `mergedFolderTombstones` (:107-120): union by `folderID`, higher `wins` replaces; grow-only, never
  expires.
- `wins()` (:270-278): higher revision; tie → newer date (`modifiedAt` folders/checklists,
  `deletedAt` tombstones); tie → lexicographically smaller `device` (tie stays when no device).
  Symmetric across local/remote.
- Checklist `folderID` is copied wholesale on a checklist LWW win (`ChecklistMerge.swift:144`); **no
  validation against `deadFolders`**. A stale `folderID` referencing a tombstoned/absent folder
  survives merge whenever its checklist wins the clock comparison — merge never revalidates (only
  store-local `deleteFolder`/`moveChecklist` guard locally).
- `ChecklistSyncCoordinator.pushContext()` (:91-93; fires on start/activated/request/change :38-75)
  passes `folders: folders()` but **empty `deviceID` and no `folderTombstones`** to the watch
  channel (:17 default `{[]}`).
- `WatchChecklistStore` holds `folders: [Folder]` mirror delivered with each context push
  (`ChecklistSync.swift:265`); `.context` receive sets checklists+folders (:349), migratable v2+
  also assigns folders (:354). No `folderTombstones` kept on watch — a tombstoned folder simply
  stops arriving.

## Q6: Test patterns and fixtures

### Findings
- All suites under `CheckStitchTests/`. Unit suites are Swift Testing (`@Test`/`#expect`); the
  store/codec suites named are XCTest (`XCTAssert*`, `@MainActor`). No `#if os(...)`/`#available`
  guards in any named suite; `@MainActor` is the active isolation gate (test targets deliberately do
  NOT default to actor isolation). No shared folder fixture helper — each suite builds its own.
- `TestFixtures.swift` (244 lines): `makeItem` (:7-12), `makeIsolatedDefaults()` (wiped UserDefaults
  suite :17-23), `sharedTestEventStore` (@MainActor global EKEventStore :33-37), plus spies/doubles
  back the store/import/export paths (:39-244).
- `ChecklistExportTests.swift` (173, XCTest): local `makeChecklists()`/`selectedPair()` (:8-21);
  round-trip via `ChecklistExport.data` → `ChecklistCodec.classify` → `.loaded` (:24-33); preserve
  priority/disabled/destination/multiple/clamp (:64-134); `ChecklistExportDocument.data` decoded
  semantically, never byte-compared (:159-173). **0 folder refs.**
- `ChecklistExportDocumentTests.swift` (12, Swift Testing): only `readableContentTypes == [.json]`.
- `ChecklistImportSessionTests.swift` (360, Swift Testing): `makeSession()` (isolated store +
  session), `payload(_:version:)` encodes an envelope (:6-18); covers stage-writes-nothing,
  commit, conflict enqueue, unsupported, unreadable, v1/v2 migration, re-import stability,
  priority/destination/multiple, replace tombstone, keepBoth, keepExisting, import-lands-active.
  **0 folder refs.**
- `ChecklistImportExportViewModelTests.swift` (351): `makeStore(names:)`, `writeTempFile(_:)`
  (:8-20); frictionless sleep via `await Task.yield()` (:242-244).
- `ChecklistCodecTests.swift` (571, XCTest): versioned `.loaded`/`.migratable`/`.unsupportedVersion`,
  pinned `PinnedV4Codec` (:536-571); **folders**: `testFoldersSurviveEnvelopeRoundTrip` builds
  `Folder(name:)` and links via `folderID` (:507-517), collapse round-trip (:465), absent folder keys
  → defaults (:454).
- `ChecklistStoreTests.swift` (2950, XCTest, VAR-969): `makeStore(defaults:key:textEditDelay:)`,
  `Clock` (:10-46); folder CRUD incl. `createFolder` disambiguation (:2675,:2683), `moveChecklist`
  (:2694,:2708), `renameFolder` (:2736), `moveFolders` (:2797).
- `ChecklistMergeTests.swift` (1250, Swift Testing): free functions `envelope(device:)`/`checklist(id:name:revision:)`
  (:11-17); LWW revision (:26), device tie-break (:45), tombstones (:65), per-field clocks (:182),
  order reconciliation (:596-746). Folder LWW at ~:877-892, remote-only folder unite :859, folder
  tombstone prunes folder keeps members :896-912.
- `ChecklistGroupingTests.swift` (169, Swift Testing): inline `Folder(name:)` + `folderID` links
  (:8-20); loose-last (:30), orphan-folder (:44), empty-folder (:52), visibility (:87-169).

## Cross-Cutting Observations
- **Export is the only envelope producer that omits folders** — every other producer
  (store persistence, sync coordinator, merge) serializes `folders`/`folderTombstones`; export
  relies on the `[]` default and explicit-writes them empty.
- **Import consumes only `version` + `checklists`**; folders are decode-but-unused on the import
  path, and `freshCopy` additionally drops each checklist's `folderID`. So folder reconstruction on
  import has two independent drop points: envelope-level (export omits folders; import ignores
  them) and checklist-level (`freshCopy` discards `folderID`).
- **Folder identity = folder `id` UUID + checklist `folderID` pointer.** Membership is solely the
  checklist's `folderID` — there is no folder-side children list. `ChecklistGrouping` and
  `visibleFolders` derive entirely from `checklist.folderID == folder.id`.
- **Folder tombstone semantics are permanent/grow-only:** nothing resurrects a deleted folder;
  merging prunes a live folder unconditionally when any tombstone names it. `deviceID:""` on export
  is deliberate so a re-import can't inject a foreign device into future LWW tie-breaks.
- **Folder merge is coarse-clock (revision/modifiedAt) LWW**; `isCollapsed` is not a separate clock
  and is carried only on a full folder LWW win.
- **Merge never revalidates `folderID`** against live/dead folders — only store-local
  `deleteFolder`/`moveChecklist` defuse stale pointers. The grouping layer treats an unknown
  `folderID` as "loose" (no crash).

## Open Areas
- Whether `isCollapsed` is honored/rendered in the watch/phone list views (only struct/codec was
  traced, not UI rendering).
- Display of a stale `folderID` in Watch folder views was not exhaustively verified.
- Exact behavior if an imported file carries a `folderID` whose folder is absent from the same file
  (relevant to reconstruction semantics — current code: imported freshCopy drops folderID entirely,
  and grouping would treat it loose if it survived).
- No import decision currently considers folders or folder collisions; `importInsert`/`importReplace`
  signatures and `freshCopy` are the write-path surface that would need to carry folder membership.