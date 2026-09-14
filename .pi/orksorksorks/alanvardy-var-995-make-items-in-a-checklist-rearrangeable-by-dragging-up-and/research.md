# Research Findings

## Q1: How the ChecklistStore mutation API works

### Findings
- `@Observable final class ChecklistStore` — `CheckStitch/ChecklistStore.swift:7`. Mutable state is `private(set)`: `checklists: [Checklist]` (line 16), `tombstones: [ChecklistTombstone] = []` (line 21); all mutation flows through the public methods.
- Constructor `init(defaults: UserDefaults, key: String = "checklists.v1", textEditDelay: Duration? = .300ms, now: () -> Date = Date.init)` — lines 42-58: loads via `ChecklistCodec.classify` (61-79), branches `.loaded`/`.migratable`/`.unsupportedVersion`/`.unreadable`, and sets `canOverwriteStoredPayload` (31, 67-73). `deviceID` is read from defaults or generated as a random UUID string (53-58). `now` is an injected closure so tests control time (40).
- Public methods (all verified against source):
  - `checklist(id: UUID) -> Checklist?` (98)
  - `create(name: String = "New checklist") -> Checklist` (107-118), always succeeds via `uniqueName` disambiguation (136-147), immediate `save()` (111)
  - `rename(id: UUID, to: String) -> RenameOutcome` (120-129; enum 10-14: `.renamed`/`.nameTaken`/`.notFound`), `scheduleSave()` (127)
  - `addItem(to id: UUID)` (154-158), immediate `save()`
  - `updateItem(checklistID: UUID, itemID: UUID, title: String)` (160-168), `scheduleSave()` (167)
  - `removeItems(from id: UUID, at offsets: IndexSet)` (170-179), immediate `save()`
  - `delete(id: UUID)` (182-188), immediate `save()`
  - `apply(remote: ChecklistEnvelope) -> Bool` (194-208), immediate `save()`
  - `flushPendingSave()` (213-218)
- **Revision/timestamp stamping**:
  - Checklist create: `modifiedAt: now(), revision: 1` (108).
  - Checklist rename: `revision += 1`, `modifiedAt = now()` (124-125); only rename bumps checklist-level revision — doc `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:54-59, 71-77`.
  - Item add: `ChecklistItem(title: "New item", modifiedAt: now(), revision: 1)` (156); parent checklist not bumped.
  - Item update: `revision += 1`, `modifiedAt = now()` (164-166), item-level only.
  - Remove/delete: survivors are **not** stamped; a `ChecklistTombstone(checklistID:, itemID:, deletedAt: now(), revision: removed.revision + 1)` is appended (175-176, 185-186) — tombstone always outranks the live revision.
- **IndexSet semantics** (only consumer today is `.onDelete` in the detail view): `offsets.sorted(by: >)` iterates descending so earlier indices stay valid; `checklists[index].items.indices.contains(offset)` bounds-guards each offset (172-173).
- **Save path**:
  - Structural edits (`create`, `addItem`, `removeItems`, `delete`, `apply`) call `save()` directly; text edits (`rename`, `updateItem`) call `scheduleSave()` (220-234) which cancels the prior timer and sleeps `textEditDelay` (default 300 ms, line 44) before saving.
  - `save()` (236-251): cancels any queued task first (239-240), refuses when `canOverwriteStoredPayload == false` (241-244), persists via `defaults.set(ChecklistCodec.encode(envelope), forKey: key)` (246), fires `onChange?()` unless `isApplyingRemote` (247).
  - `flushPendingSave()` (213-218) cancels the debounce Task and saves synchronously — called from view disappear (`ChecklistDetailView.swift:76`) and app leave-foreground paths.
  - `envelope` getter (85-91) is the only object encoded: `ChecklistEnvelope(version: currentVersion, deviceID:, checklists:, tombstones:)`.
- `onChange` is wired to `schedulePush()` by `ChecklistSyncService.start()` (`CheckStitch/ChecklistSyncService.swift:48`), so every local save (except remote-applies, which the coordinator pushes itself) triggers a debounced iCloud push.

## Q2: How ChecklistDetailView renders and mutates the item list

### Findings
- `struct ChecklistDetailView: View` keyed by `checklistID: UUID` (lines 6-8); store and dismiss come from `@Environment` (9-10). Explicitly *not* a parent `@Binding` — mutations route through the store (comment 4-5). Local `@State`: `draftName`, `didLoadDraft`, `isRemoving`, `isNameConflictPresented` (11-18).
- Body re-reads the store every frame: `if let checklist = store.checklist(id: checklistID)` (21), then a `Form` (22) with `Section("Checklist name")` → `TextField("Name", text: $draftName)` (23-24) and `Section("Items")` (27).
- **Item loop**: `ForEach(checklist.items) { item in TextField("Item", text: titleBinding(...)) }` (28-29). No explicit `id:` mapping is passed to this `ForEach`.
- **Delete affordance**: the `ForEach` chains `.onDelete { offsets in store.removeItems(from: checklistID, at: offsets) }` (30-33) — SwiftUI's edit-mode multi-select, delivering an `IndexSet` of row offsets. This is the only reorder-adjacent affordance in the repo: case-insensitive grep for `onMove|onReorder|drag|reorder` across all `*.swift` files returns **zero** matches.
- **Per-item binding**: `titleBinding(checklistID:, itemID:) -> Binding<String>` (112-122); `get:` re-reads `store.checklist(id:)?.items.first { $0.id == itemID }?.title ?? ""` (114-116); `set:` calls `store.updateItem(checklistID:, itemID:, title: $0)` (117) — every keystroke routes to the store's debounced path.
- **Add**: "Add Item" button → `store.addItem(to: checklistID)` (36-40). **Remove checklist**: destructive button sets `isRemoving = true`, `store.delete(id:)`, `dismiss()` (41-48); the `else if !isRemoving` branch (86-90) shows `ContentUnavailableView` only if deleted elsewhere.
- **Rename** is buffered, not per-keystroke: `draftName` seeded in `.onAppear` guarded by `didLoadDraft` (66-70); "Done" calls `commitRename()` (53-60 → 95-102): `.renamed`/`.notFound` → `dismiss()`, `.nameTaken` → conflict alert (78-84).
- **View disappear** (72-77): `commitDraftIfChanged()` (105-110, renames only if stored name differs) then `store.flushPendingSave()` (76).
- End-to-end: `Form/ForEach` → `Binding` (112-122) → `ChecklistStore.{updateItem,addItem,removeItems,rename,delete}` → in-memory mutation + stamps → `save()`/`scheduleSave()` → `onChange` → sync service.

## Q3: How ChecklistMerge combines local and remote envelopes

### Findings
- `enum ChecklistMerge` with pure static `merge(local:, remote:) -> ChecklistEnvelope` — `CheckStitch/ChecklistMerge.swift:11-12` (function body 12-35); no store, no I/O (doc 4-10).
- `merge` (13-34): unions tombstones first (13), computes dead checklists where `itemID == nil` (14) and removes them after conflict merging (21), suppresses per-item tombstones within each surviving checklist (22-27), and re-stamps the result `version: ChecklistCodec.currentVersion`, `deviceID: local.deviceID` (29-34). The result always advertises the local device regardless of which side won.
- `mergedTombstones` (42-62): union keyed by `(checklistID, itemID)` (`TombstoneKey`, 37-40); conflicts won by `wins` on `revision` then `deletedAt` — **no device tiebreak** (45-52); output sorted deterministically by key (57-61) so re-merging an unchanged payload is a no-op.
- `mergedChecklists` (64-93): `result = local` — **local array order is the base** (68); remote-only checklists appended at the end in remote iteration order (71-74); on conflict only `name`/`revision`/`modifiedAt` are copied over when the remote wins (78-85); `merged.items` is always recomputed from both sides via `mergedItems`, win or lose (86-89).
- `mergedItems` (95-114): same shape — `result = local` **(local item order preserved**, 99); remote-only items appended at the end (102-106); on conflict the **entire winning remote item struct replaces the local one at its local index** (108-111). Net: a remote reorder is never adopted; shared items keep the local device's relative order.
- `wins(revision:, date:, device:, over*) -> Bool` (116-122): (1) higher `revision`, (2) newer `modifiedAt`/`deletedAt`, (3) lexicographically smaller device id; device tiebreak only when both device strings are non-nil, else `false`. Symmetric, so both peers compute the same winner (doc 4-10).
- Tombstones **always** suppress their live entry regardless of the live entry's revision or date (doc 7-9); confirmed by tests `CheckStitchTests/ChecklistMergeTests.swift:65-93` (rev-1 tombstone kills rev-5 checklist; rev-2 item tombstone kills rev-1 item).
- Sole call site: `ChecklistStore.apply(remote:)` — `ChecklistStore.swift:194-208`: guards `canOverwriteStoredPayload` (195) and `remote.version == currentVersion` (198), merges (199), bails when idempotent `merged != envelope` (200), returns `visibleChanged = merged.checklists != checklists` (201), installs state under `isApplyingRemote` (202-207) so `save()` suppresses `onChange` (247).

## Q4: The checklist data model and its encoding

### Findings
All refs to `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` unless noted.
- `ChecklistItem: Identifiable, Codable, Hashable, Sendable` (13). Fields: `let id: UUID` (stable identity, "so rows can be added, removed, and edited without conflating duplicate titles", comment 9-12), `var title`, `var modifiedAt: Date`, `var revision: Int` (14-41); computed `isBlank` trims whitespace/newlines (44-46).
- `Checklist` (60): `let id`, `var name`, `var items: [ChecklistItem]`, `var modifiedAt`, `var revision` (62-84); doc 54-59: checklist-level `modifiedAt`/`revision` describe the record, only a rename bumps them (items merge independently).
- `ChecklistTombstone` (108-120): `checklistID: UUID`, `itemID: UUID?` (nil = whole-checklist deletion), `deletedAt`, `revision`.
- `ChecklistEnvelope` (124-157): `version`, `deviceID`, `checklists`, `tombstones`; decode tolerates missing `deviceID`/`tombstones` (v1) (142-149).
- **Codable protocol**: `ChecklistItem` `CodingKeys {case id, title, modifiedAt, revision}` (48); `init(from:)` uses `decodeIfPresent` with `.distantPast`/0 defaults so v1 payloads load (50-57); `encode` writes all four (59-65). `Checklist` CodingKeys include `items` (86); decode defaults `[]`/`.distantPast`/0 (88-101). Encoding is plain `JSONEncoder()` (188-189).
- **Codec versioning/migration**: `currentVersion = 2` (169). `classify` (194-211) decodes a `VersionProbe {let version: Int}` (222): `== currentVersion` → `.loaded(envelope)`; `== 1` → `.migratable(from: 1, checklists:)`; other → `.unsupportedVersion`; decode throw → `.unreadable`. `decode` convenience (214-220). `Checklist.migrated(at:)` (91-102) stamps `modifiedAt = date` and `revision = max(revision, 1)` on the checklist and every item.
- `contentEquals(_ other: ChecklistEnvelope) -> Bool` (160-166): `version == other.version && checklists == other.checklists && tombstones == other.tombstones` — **ignores deviceID**, and array `==` is **order-sensitive** on both `checklists` and `items`. This is the predicate the sync path uses to decide whether to push back.
- **Every touch point of an item's persisted bytes**:
  - App Group defaults write: `ChecklistStore.save()` → `defaults.set(ChecklistCodec.encode(envelope), forKey: key)` (`CheckStitch/ChecklistStore.swift:246`).
  - App Group defaults read: init → `defaults.data(forKey: key)` + `classify` (57-79).
  - Cloud KVS read/write: `UbiquitousChecklistSync.read()/write()` on `store.data(forKey:)`/`store.set(...)` (`ChecklistSyncing.swift:28-29`).
  - Sync service: seed-write (ChecklistSyncService.swift:115-120), migrate-then-apply (126-136), push-back encode+write (137-140).
  - Watch path: `ChecklistSyncCoordinator.pushContext()` encodes an envelope with `deviceID: ""` (`ChecklistSyncCoordinator.swift:30-32`); `ChecklistSync.receive(.context)` decodes via `classify`, keeping the old list if not `.loaded` (`ChecklistSync.swift:99-105`).
  - Byte-format tests: `CheckStitchTests/ChecklistCodecTests.swift:7-62` (round-trip, v1-migratable, unknown-version-empty, unreadable-vs-unsupported, v1-without-`isBlank`).

## Q5: How the iCloud sync pipeline works end to end

### Findings
- **Service**: `ChecklistSyncService(sync: any ChecklistSyncing, store: ChecklistStore, pushDelay: Duration? = .500ms)` — `CheckStitch/ChecklistSyncService.swift:24-27`. `start()` (38-43) wires the two triggers: KVS external-change observation → `reconcile()` (40-41) and `store.onChange` → `schedulePush()` (48).
- **Triggers**: `syncOnLaunch()` (48-55) calls `sync.synchronize()` first ("Nudge KVS to pull before the first read"), then reconciles; `refresh()` (57-61) same for pull-to-refresh.
- **Coalescing** `reconcile()` (67-80): concurrent callers share one in-flight pass via `inFlight`/`inFlightID`.
- **Debounce** `schedulePush()`/`pushNow()` (63-72/59-62): `schedulePush` cancels any pending task and sleeps `pushDelay`; `pushNow` cancels it and runs `reconcileNow()` **synchronously** — the deliberate bypass so a backgrounded app still pushes before suspension.
- **`reconcileNow()`** (86-142): (1) `isSyncing = true` (87-88); (2) guard `store.canAcceptRemoteChanges` (90); (3) `sync.read()` (92); (4) `nil` → seed cloud with local only when local is non-empty, never push empty (94-105); (5) `classify` (107-114): `.loaded` adopts, `.migratable` re-wraps with `migrated(at: .distantPast)` and `deviceID: ""` (129-130), `.unsupportedVersion`/`.unreadable` fail without touching local (131-134); (6) apply + push-back: `visibleChanged = store.apply(remote:)`; `if visibleChanged || !store.envelope.contentEquals(remote)` → `sync.write(encode(store.envelope))` + `sync.synchronize()` (137-140).
- **KVS adapter**: `UbiquitousChecklistSync` (`ChecklistSyncing.swift:20-44`) wraps `NSUbiquitousKeyValueStore.default` under key `"checklists.v1"` (22-23): `read` = `store.data(forKey:)` (28), `write` = `store.set` (29), `synchronize` (30); observer on `NSUbiquitousKeyValueStore.didChangeExternallyNotification`, hopping via `MainActor.assumeIsolated` before calling back (32-44). This is the **only** `NSUbiquitousKeyValueStore` usage in the repo. `NotificationObservation.cancel()` (50-63) is idempotent.
- **Merge invocation**: `store.apply(remote:)` → `ChecklistMerge.merge(local: envelope, remote:)` (`ChecklistStore.swift:199`); idempotence guard `merged != envelope` (200); no-op applies return `false` before any save, so no `onChange` and no push.
- **Order sensitivity — why reorder sync is asymmetric**: `contentEquals` is order-sensitive over `checklists`/`items` (Q4). Trace for a pure local reorder:
  1. Local device reorders → `save()` → `onChange` → `pushNow` → `reconcileNow` → `apply(remote)` → `mergedItems` keeps **local** (reordered) order → `visibleChanged == false` (merged == local), but `!contentEquals(remote)` is true → the local device **pushes its reordered envelope** to iCloud.
  2. Remote device (unreordered) sees the KVS change → `reconcile` → `apply(reordered remote)` → `mergedItems` keeps **its own** (unreordered) local order, remote-only items appended → reorder silently discarded; then since `!contentEquals(remote)` is true, **it pushes its unreordered envelope back**.
  3. Converges only in the sense that both devices push; the KVS holds whichever wrote last, and each device keeps its own order locally. Cross-device ordering is never converged by merge. This is the factual basis for the ticket's "a local reorder will not sync" claim.
- Push-back compares *local-after-apply* against *remote-as-read* using the deviceID-ignoring `contentEquals` (137 vs Checklist.swift:160-166).

## Q6: Test suites, fixtures, and drag/reorder affordances

### Findings
- Suite root `CheckStitchTests/` (28 `.swift` files incl. fixtures; macOS-hosted, `make test-unit`) plus one UI smoke in `CheckStitchUITests/CheckStitchUITests.swift:13` (`testLaunchAndAccessibilitySmoke` — accessibility-identifier asserts 14-19, empty-state handling 21-28, performance audit with `#if os(iOS)` split 33-42).
- **Two test styles coexist**: XCTest (`import XCTest`, `final class X: XCTestCase`, `@MainActor`) — `ChecklistStoreTests.swift:1-7`, `ChecklistCodecTests.swift`; Swift Testing (`import Testing`, `struct X`, `@Test`) — `ChecklistMergeTests.swift:1-10`, `ChecklistItemTests.swift`, `ChecklistSyncServiceTests.swift`, `ChecklistSyncCoordinatorTests.swift`, `ChecklistSyncMessageTests.swift`, `WatchChecklistStoreTests.swift`. Both use `@MainActor`; the store suite adds `@testable import CheckStitch` for white-box app-target access (2).
- **Store test patterns** (`ChecklistStoreTests.swift`): fresh uniquely-named `UserDefaults` suite per test (`makeDefaults`, 11-14) + `defer` cleanup (29-31); reload-after-mutation by constructing a second store on the same defaults (`testCreatePersistsAcrossReload` 28-42, `testRenamePersists` 46, `testAddAndRemoveItemPersists` 58, `testRemoveItemsLeavesItemTombstones` 389/411-412); raw payload assertions via `ChecklistCodec.decode` (40-42); deterministic `Clock` helper (25); debounce opted out via `textEditDelay: nil` except two debounce tests (20-22, 139, 159); stamp assertions (`testMutationsStampRevisionAndTimestamp` 343); apply/merge (`testApplyMergesRemoteChecklist` 413, `testApplyIsIdempotent` 453, `testApplyRefusesFutureVersion` 471); `testOnChangeFiresForLocalSavesButNotWhenApplyingRemote` 501.
- **IndexSet testing**: only as `IndexSet(integer: N)` single offsets to `removeItems` (`ChecklistStoreTests.swift:68, 399-400`); no dedicated IndexSet suite. Production use: `ChecklistStore.swift:170-179`.
- **Merge test patterns** (`ChecklistMergeTests.swift`): local fixture builders `envelope()/checklist()/item()/tombstone()` (161-181), symmetry checked by passing both argument orders (26), LWW tie-break (45, 118), tombstone suppression (65-93), no-op on identical envelopes (139).
- **Fakes** (`CheckStitchTests/TestFixtures.swift`): `InMemoryChecklistSync` (52, with `written`/`readCount`/injectable errors/`fireExternalChange()` 89), `InMemoryObservation` (96), `FakeChecklistSyncTransport`, `SpyReminderCreator` (42), `SpyChecklistRunner`, `makeIsolatedDefaults` (11), `sharedTestEventStore` (30), `TestError` (105-107).
- **Drag/reorder affordances**: none. Repo-wide case-insensitive grep for `onMove|onReorder|drag|reorder` in all `*.swift` files: zero matches. The only IndexSet consumer and the only select/delete affordance is `.onDelete` (`ChecklistDetailView.swift:30-33`).

## Cross-Cutting Observations
- **Store is the choke point**: the UI never mutates state directly (bindings and callbacks route through `ChecklistStore`); the store is the sole writer of persisted bytes (`ChecklistStore.swift:246`), the sole caller of `ChecklistMerge.merge` (199), and the sole source of `onChange` (247).
- **Order is not merged, it is inherited**: `mergedItems`/`mergedChecklists` base on the local array and append remote-only entries (`ChecklistMerge.swift:68-74, 99-106`); item identity is `id` + per-item `revision`/`modifiedAt` (`Checklist.swift:14-19`), and conflict resolution replaces the whole winning struct at the local position (108-111).
- **Order-sensitivity is pervasive downstream**: `contentEquals` and `apply`'s `visibleChanged` are order-sensitive (`Checklist.swift:160-166`, `ChecklistStore.swift:201`), so a reorder is byte-visible to sync even though it changes no item fields; tombstone ordering is deliberately canonicalized so re-merging is a no-op (`ChecklistMerge.swift:57-61`).
- **Stamp discipline**: only `addItem` and `updateItem` stamp items (`ChecklistStore.swift:156, 164-166`); `removeItems`/`delete` never touch survivors. A move that leaves `modifiedAt`/`revision` untouched preserves item identity by construction.
- **LWW symmetry**: `wins` is symmetric on revision → timestamp → deviceID (`ChecklistMerge.swift:116-122`), and the merge result always wears `local.deviceID` (29-34) — correctness depends on both peers computing the same winner.
- **Migration is one-way and stamping**: v1 payloads gain `modifiedAt`/`revision` via `migrated(at:)` (Checklist.swift:91-102), so pre-sync data gets item revisions ≥ 1 and distant-past-ish ordering timestamps.
- **Debounce vs structural save**: text edits coalesce at 300 ms (`ChecklistStore.swift:220-234`), structural edits save immediately and cancel any queued timer; `flushPendingSave` runs on view disappear and app leave-foreground (`ChecklistDetailView.swift:76`, `MyApp.swift:52, 81`).
- **Tests are store-centric**: the dominant suite constructs stores over fake `UserDefaults` and asserts reloaded state — a natural template for any new store mutation, including `IndexSet`-driven ones (move cases would mirror `IndexSet(integer:)` usage at `ChecklistStoreTests.swift:68, 399-400`).

## Open Areas
- **KVS wire semantics**: `UbiquitousChecklistSyncTests.swift` contains construction/cancel canaries only — no real KVS I/O on the host — so last-writer-wins timing across devices, sync failures mid-push, and cross-device convergence under concurrent reorders are not empirically covered in-repo.
- **SwiftUI `.onMove` requirements**: the repo has no `onMove` usage or `List`-with-move sample; whether the framework's move affordance requires an explicit `id:` mapping on the `ForEach` and how `from:`/`to:` indices are delivered is framework knowledge not discoverable from this codebase (the detail view's `ForEach` currently passes no `id:` — `ChecklistDetailView.swift:28`).
- **Remote reorder behavior**: because merge never adopts a remote ordering, there is no code path today that would ever bring one device's ordering to another — nothing in the codebase models "ordering" as mergeable state (no sort field exists on `ChecklistItem` or `Checklist`).
- **Item `position`/`sortOrder` field**: no trace of such a field anywhere (model, codec, merge, or tests); the schema/merge/encoding surface it would touch is fully enumerated in Q3/Q4.