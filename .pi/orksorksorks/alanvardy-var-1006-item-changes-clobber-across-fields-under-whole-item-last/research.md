# Research Findings

All line numbers verified against the working tree on 2026-09-15.

## Q1: How `ChecklistMerge` resolves conflicts, and what it copies for a winner

### Findings
- `CheckStitch/ChecklistMerge.swift` is a pure, deterministic merge (imports
  only `CheckStitchCore` + `Foundation`). Entry point `merge(local:, remote:)`
  at `ChecklistMerge.swift:12`: unions tombstones (`:13`), derives
  `deadChecklists` (tombstones with `itemID == nil`) and `itemTombstones`
  (`:14-15`), merges checklists (`:17`), then suppresses the dead: removes
  dead checklists (`:21`), and per surviving checklist removes dead item ids
  from `items` and `itemOrder` (`:23-27`).
- **`wins` comparator** (`ChecklistMerge.swift:166`): higher `revision` wins
  (`:168`), else newer `date` (`:169`), else lexicographically smaller
  device id (`:170-171`); without device ids, no win (`:170`). Symmetric and
  transitive — both sides compute the same winner. Used at every merge level.
- **Tombstones** (`mergedTombstones`, `ChecklistMerge.swift:43-63`): keyed by
  `TombstoneKey(checklistID, itemID)` (`:38`); conflict resolved with the
  same `wins` using `deletedAt` as the date (`:50-52`). Output sorted by
  `(checklistID, itemID)` so re-merging is a no-op (`:59-62`). Suppression is
  absolute: a tombstone always kills the live entry (`:21`, `:26-27`).
- **Checklist level** (`mergedChecklists`, `ChecklistMerge.swift:65-114`):
  remote-only checklists are appended whole (`:125` for items analog);
  same-id checklists start from the local record; if the remote wins
  (`:79-82`), exactly four fields are copied: `name` (`:83`),
  `destinationListIdentifier` (`:84`), `revision` + `modifiedAt` (`:85-86`).
  Items and order are merged separately afterwards.
- **Item level** (`mergedItems`, `ChecklistMerge.swift:116-135`): remote-only
  items are appended whole (`:125`); for a same-id conflict, if the remote
  item wins (`:129-130`) then `result[index] = remoteItem` (`:131`) — the
  **entire `ChecklistItem` struct** (title, description, relativeDate,
  revision, modifiedAt, id) is replaced. There is no per-field merge; a
  losing item's field edits are clobbered even when the loser edited a
  different field later.
- **Order** (`ChecklistMerge.swift:93-110`): order has its own independent
  LWW via `orderRevision`/`orderModifiedAt` (`:93-98`); the winner's
  `itemOrder` is reconciled against surviving merged items
  (`reconciledOrder` `:141`, dedup via `seen`), the winning order stamps
  transfer only when the order LWW is remote (`:107-110`).
- **Call site**: the single production caller is
  `ChecklistStore.apply(remote:)` at `ChecklistStore.swift:325`, which guards
  on `canOverwriteStoredPayload` (`:321`) and `remote.version == currentVersion`
  (`:323-324`).

## Q2: Semantics and lifecycle of per-item sync state and tombstones

### Findings
- `ChecklistItem` (struct at `Checklist.swift:6`) carries `modifiedAt:
  Date = .distantPast` and `revision: Int = 0` (init defaults, `:7-13`;
  fields `:19-20`). Doc comment (`:5`): both are "the sync identity the
  merge compares"; both optional on decode so v1 payloads (no sync state)
  still load. Decode defaults: `description ?? ""`, `modifiedAt ??
  .distantPast`, `revision ?? 0`, `relativeDate` absent → nil
  (`Checklist.swift:50-55`).
- `Checklist`'s own `modifiedAt`/`revision` are explicitly **not** the
  items': "a rename or a destination change bumps them … items merge
  independently on their own `modifiedAt`/`revision`" (`Checklist.swift:80-83`).
- Store stamping per mutation (`ChecklistStore.swift`; every item/checklist
  op calls `save()`/`scheduleSave()`):

  | Mutation | Stamps | Values |
  |---|---|---|
  | `create` (`:127`) | checklist | `modifiedAt: now()`, `revision: 1` |
  | `duplicate` (`:148`) | checklist + each item | items get new UUID, `revision: 1`, `modifiedAt: now()` |
  | `rename` (`:170`) | checklist | `revision += 1`, `modifiedAt = now()` |
  | `setDestination` (`:186`) | checklist | `revision += 1`, `modifiedAt = now()` |
  | `addItem` (`:217`) | new item | `revision: 1`, `modifiedAt: now()`; appended to `itemOrder` |
  | `updateItem` title (`:225`) | item | `revision += 1`, `modifiedAt = now()` — **no unchanged guard; every write bumps** |
  | `updateItemDescription` (`:238`) | item | same — **no guard** |
  | `updateItem` relativeDate (`:252`) | item | guard `relativeDate != relativeDate else { return }` — **only a changed value is an edit** (`:256`) |
  | `removeItems` (`:263`) | item tombstone | `ChecklistTombstone(…, deletedAt: now(), revision: removed.revision + 1)` |
  | `moveItems` (`:296`) | ordering only | `orderRevision += 1`, `orderModifiedAt = now()` — item identity unstamped |
  | `delete` (`:308`) | checklist tombstone | `revision: removed.revision + 1` |
- "What counts as an edit": title/description — any write (keystrokes
  coalesced by the 300 ms `scheduleSave` debounce, `ChecklistStore.swift:351-363`,
  default `:52`); relativeDate — only a changed value, so a text field
  re-committing the same parse cannot win a spurious LWW round
  (`ChecklistStore.swift:252-256`); reorder — not an item edit.
- Tombstones are append-only, never compacted (`ChecklistStore.swift:26-28`).
  Because a tombstone's `revision` is always `removed.revision + 1` (one
  greater than the live record), it outranks any live copy: a deletion made
  on one device can never be resurrected by an older copy on another
  (`ChecklistMerge.swift:7-9`, `:50-52`).
- Load-time stamping: v1 payloads → `migrated(at: now())` stamps checklist +
  each item `modifiedAt = date`, `revision = max(revision, 1)` and seeds
  ordering (`Checklist.swift:160-176`); v2 → `seededOrder()` seeds only the
  order state, never restamping item/checklist sync state
  (`Checklist.swift:186-196`); v3+ loaded verbatim, "a stored
  revision/modifiedAt is never restamped" (`ChecklistStore.swift:84-85`).
- Tombstones in the codec: envelope `tombstones` decodes
  `decodeIfPresent ?? []` (`Checklist.swift:262`), encodes at `:270`.
  `ChecklistTombstone` (`:222`) declares `Codable` with **no explicit
  CodingKeys** — its wire shape is the compiler-synthesized codec (field
  order `checklistID, itemID, deletedAt, revision`, `:223-230`).

## Q3: Codec serialization, versioning, backward compatibility

### Findings
- **Keys written per type** (all verified):
  - `ChecklistItem` — `CodingKeys { id, title, description, modifiedAt,
    revision, relativeDate }` (`Checklist.swift:43`); encoder writes every
    key, including `relativeDate` explicitly via `encode`/`encodeNil` so the
    key is never omitted (`:63-79`).
  - `Checklist` — `{ id, name, items, destinationListIdentifier, modifiedAt,
    revision, itemOrder, orderRevision, orderModifiedAt }` (`:118`); decode
    self-heals through `normalizedOrder()` (`:200`) which appends missing
    item ids and dedupes.
  - `ChecklistEnvelope` — `{ version, deviceID, checklists, tombstones }`
    (`:254`).
  - `ChecklistTombstone` — synthesized codec (no explicit keys).
- **Decoder defaults**: item — `id`/`title` mandatory, `description ?? ""`,
  `modifiedAt ?? .distantPast`, `revision ?? 0`, `relativeDate` → nil
  (`Checklist.swift:47-55`); checklist — `items ?? []`,
  `destinationListIdentifier` → nil, `itemOrder ?? items.map(\.id)`,
  `orderRevision ?? 0`, `orderModifiedAt ?? .distantPast` (`:121-132`);
  envelope — `version` mandatory, `deviceID ?? ""`, `checklists ?? []`,
  `tombstones ?? []` (`:258-262`).
- **Versioning**: `currentVersion = 4` (`Checklist.swift:283`). `classify`
  (`:310-338`) probes only `version` (via `VersionProbe`, `:348`) before
  full decode:
  - `4` → `.loaded`; `3` → `.migratable(from: 3)` verbatim, never restamped
    ("predates `relativeDate`"); `2` → `.migratable(from: 2)` (sync state,
    no ordering); `1` → `.migratable(from: 1)`;
  - any other version → `.unsupportedVersion`; any thrown decode →
    `.unreadable`.
  - `decode` (`:340-345`): `.loaded`/`.migratable` → `checklists`,
    else `[]`.
- **Backward-compatibility mechanics**:
  - Fewer keys: every field except `Item.id`/`title`, `Checklist.id`/`name`,
    `Envelope.version` is `decodeIfPresent` with a default — v1/v2 bytes
    (no description, relativeDate, destination, order keys, deviceID,
    tombstones) load via defaults.
  - More keys / newer app: `classify` reads `version` first, so a v5+
    payload is `.unsupportedVersion` without body decode, and the store
    becomes read-only for it (`ChecklistStore.swift:92` sets
    `canOverwriteStoredPayload = false`).
  - **Additive optional keys come without a version bump**: `description`
    was added absent-key-tolerant "matching the `destinationListIdentifier`
    precedent — no version bump" (`Checklist.swift:53-54`); `relativeDate`
    likewise. Only whole-key absence is tolerant — a wrong-typed value
    (e.g. `"description": 42`) throws and the whole payload becomes
    `.unreadable`.
  - `classify` consumers: store load (`ChecklistStore.swift:69`), sync
    reconcile (`ChecklistSyncService.swift:120-134`), KVS seam
    (`ChecklistSyncing.swift:33-41` startObserving region).

## Q4: End-to-end path of an item edit (UI → remote store)

### Findings
- **UI bindings** (`CheckStitch/ChecklistDetailView.swift`): `ItemRow`
  receives per-item `title:`/`description:` bindings plus `relativeDate`
  (`:66-71`). `titleBinding` (`:195-202`): `get` re-finds the item by id
  (missing → `""`), `set` → `store.updateItem(checklistID:, itemID:, title:)`
  (`:200`). `descriptionBinding` (`:206-212`): `set` →
  `store.updateItemDescription(..., description:)` (`:211`). `relativeDate`
  goes through a `@State draftDate` buffer (`:291`) seeded from the model
  (`:307`), updated on external iCloud change (`:314-315`), committed via
  `.onChange(of: draftDate)` → `commitRelativeDate(Self.parse(newValue))`
  (`:332-334`, `:340-342`).
- **Store mutator → debounce → encode → persist**: `updateItem` title
  (`ChecklistStore.swift:225-236`), `updateItemDescription` (`:238-250`),
  `updateItem` relativeDate (`:252-262`) each bump the item's
  `revision`/`modifiedAt` and call `scheduleSave()` (`:351-363`, 300 ms
  coalescing, default `:52`). `save()` (`:365-380`) refuses while
  `canOverwriteStoredPayload == false` (`:370`), writes
  `defaults.set(ChecklistCodec.encode(envelope), forKey: "checklists.v1")`
  (`:372`, key `:51`), and fires `onChange?()` unless `isApplyingRemote`
  (`:376`).
- **Local → push**: `MyApp.swift:29-30` builds
  `ChecklistSyncService(sync: UbiquitousChecklistSync(), store:)` and calls
  `start()`. `ChecklistSyncService.start()` (`ChecklistSyncService.swift:43-50`)
  wires `sync.startObserving { reconcile() }` and `store.onChange =
  schedulePush` (`:48`). `schedulePush` (`:91-98`) debounces 500 ms
  (`pushDelay`, `:26`) then `pushNow()` (`:85-89`) runs `reconcileNow()`
  synchronously. Launch reconcile on macOS `:46` / iOS `:76`
  (`syncOnLaunch`).
- **reconcileNow** (`ChecklistSyncService.swift:101-161`): guards
  `store.canAcceptRemoteChanges` (`:105`); `sync.read()` (`:108`); empty
  cloud seeds only when local is non-empty, never writing over unseen data
  (`:110-121`); `ChecklistCodec.classify` — `.migratable` maps v1 → 
  `migrated(at: .distantPast)` with `deviceID: ""`, v2 → `seededOrder()`,
  v3+ verbatim; `.unsupportedVersion`/`.unreadable` →
  `finish(.failed(...))` without touching local (`:131-133`). Then
  `store.apply(remote:)` (`:154`) and, only if
  `visibleChanged || !envelope.contentEquals(remote)`, writes the merged
  envelope back and `sync.synchronize()` (`:155-158`).
- **KVS seam**: `UbiquitousChecklistSync` wraps one long-lived
  `NSUbiquitousKeyValueStore` under key `"checklists.v1"`
  (`ChecklistSyncing.swift:23`): `read` `:28`, `write` `:29`,
  `synchronize` `:30`. `startObserving` (`:33-41`) subscribes to
  `NSUbiquitousKeyValueStore.didChangeExternallyNotification` and hops onto
  the main actor (`:40`). Sole KVS use in the repo (the app target's
  `ContentView.swift:417` also wires a sync service in its environment).
- **apply(remote:)** (`ChecklistStore.swift:320-337`): refuses when
  `canOverwriteStoredPayload` is false (`:321`) or version ≠ current
  (`:323-324`); `ChecklistMerge.merge(local: envelope, remote:)` at `:325`;
  self-heals `normalizedOrder()`; idempotence guard `merged != envelope`
  (`:330`); installs state under `isApplyingRemote = true` (`:331`) and
  saves (suppressing `onChange`); returns whether visible state changed.
- **Guards**: `canOverwriteStoredPayload` is computed at load
  (`ChecklistStore.swift:73, :89, :92, :95, :99`) — `.unsupportedVersion`
  → `false`, everything else (`loaded`/`migratable`/`unreadable`) → `true`;
  exposed as `canAcceptRemoteChanges` (`:114`). `contentEquals`
  (`Checklist.swift:277-278`) compares version/checklists/tombstones
  **ignoring `deviceID`**, and decides the push-back in `reconcileNow`
  (`ChecklistSyncService.swift:155`).
- **Who calls `mergedItems`**: `merge` (`ChecklistMerge.swift:12`) →
  `mergedChecklists` (`:17`) → `mergedItems` (`:89`) → `ChecklistStore.apply`
  (`ChecklistStore.swift:325`) → `ChecklistSyncService.reconcileNow`
  (`ChecklistSyncService.swift:154`). Nothing else in production.

## Q5: What the merge/codec/sync test suites cover

### Findings
- **`ChecklistMergeTests`** — Swift Testing `struct` (`ChecklistMergeTests.swift:7`).
  LWW: `higherRevisionWinsInEitherArgumentOrder` `:26`,
  `equalRevisionAndTimestampBreakTiesByDeviceID` `:45`,
  `sameItemEditedOnBothDevicesUsesLWW` `:118`,
  `descriptionFollowsTheWholeItemLWinner` `:139` (documents today's behavior
  that description follows the whole-item LWW winner). No-clobber/union:
  `itemEditsFromBothDevicesSurvive` `:96`,
  `distinctItemDescriptionsBothSurvive` `:152`. Tombstones:
  `tombstonedChecklistIsNeverResurrected` `:65`. Idempotence:
  `identicalEnvelopesAreANoOp` `:164`. Time injected as fixed
  `Date(timeIntervalSince1970:)` literals; comparison via `#expect` and
  `contentEquals`.
- **`ChecklistCodecTests`** — XCTest `final class` (`ChecklistCodecTests.swift:6`).
  Round-trips: `testEnvelopeRoundTrip` `:7`, `testV3RoundTripPreservesOrder`
  `:103`. Migration/classify: `testLegacyV1PayloadIsClassifiedMigratable`
  `:29`, `testUnknownVersionDecodesAsEmpty` `:43`, `testFutureVersionIsUnsupported`
  `:98`, `testItemWithoutDescriptionClassifiesLoadedAsEmpty` `:168`,
  `testMalformedDescriptionMakesPayloadUnreadable` `:193`. Method: raw JSON
  string literals with interpolated UUIDs, `XCTAssertEqual` on `classify`
  outcomes, byte-level `String(data:encoding:)` checks.
- **`ChecklistStoreTests`** — XCTest `final class` (`ChecklistStoreTests.swift:6`),
  unique `UserDefaults` per test (`:10-15`), injectable `Clock`
  (`:39`) used by the stamping tests, `textEditDelay: nil` except the
  debounce pair. Stamping semantics: `testMutationsStampRevisionAndTimestamp`
  `:394`, `testDescriptionEditBumpsItemRevisionNotChecklist` `:419`,
  `testMovePreservesItemIdentity` `:653`. Migration:
  `testLegacyPayloadIsMigratedAndSavable` `:310`,
  `testV2PayloadLoadsWithoutRestampingAndSeedsOrdering` `:365`. Guards:
  `testUnsupportedVersionPayloadIsNotOverwritten` `:137`,
  `testTextEditsAreCoalescedUntilFlush` `:152`. Includes an
  `apply(remote:)` block (merge applies, idempotence, future-version
  refusal, onChange suppression).
- **`ChecklistSyncServiceTests`** — Swift Testing `struct`
  (`ChecklistSyncServiceTests.swift:7`), `InMemoryChecklistSync` fake,
  `pushDelay: nil`. Scenarios: `emptyCloudSeedsNonEmptyLocal` `:29`,
  `cloudV1PayloadIsMigratedOnReconcile` `:65`,
  `descriptionSurvivesMergeAndPush` `:129` (asserts via
  `ChecklistCodec.decode` on the pushed bytes),
  `bothNonEmptyMergeAndPush` `:149`, `unreadableRemoteIsIgnored` `:220`,
  `observerCallbackTriggersReconcile` `:240` (only suite needing a real
  `Task.sleep`).
- **Watch/KVS suites**: `ChecklistSyncCoordinatorTests` `:6` (start/run/
  activation, fake transport, `ChecklistCodec.decode` of pushed contexts),
  `WatchChecklistStoreTests` `:6` (context replace, v2 compat, run once,
  destination/description survive the transport), `UbiquitousChecklistSyncTests`
  `:5` (construction canary only — no KVS calls in the test host).
- **Coverage mapping to the ticket's scenario list**: LWW wins — merge `:26,
  :45, :118, :139`; tombstones — merge `:65`, store `:137` region/`:365`,
  codec `:29`; distinct ids — merge `:96, :152`, store duplicate block;
  v1/v2/v3 migration — codec `:29, :103`, store `:310, :365`, service `:65`;
  unknown versions — codec `:43, :98`, store `:137`; round-trips — codec
  `:7, :103`, store; idempotence — merge `:164`, store apply block,
  service `:149`. No suite yields to a live clock.

## Q6: Which code paths mutate title, description, and the date field

### Findings
- **Title** — `updateItem(checklistID:, itemID:, title:)`
  (`ChecklistStore.swift:225-233`): unconditionally writes `title`, bumps
  `revision += 1` / `modifiedAt = now()`, `scheduleSave()`. No no-op guard;
  missing ids are silent `guard … else { return }` no-ops (`:226-228`).
- **Description** — `updateItemDescription` (`ChecklistStore.swift:238-246`):
  mirror of the title mutator; doc comment (`:236-237`) states it "edits
  only the item's description, stamping the item's sync identity … Item ops
  never touch the checklist's own `revision`/`modifiedAt`". No guard.
- **relativeDate** — `updateItem(..., relativeDate: Int?)`
  (`ChecklistStore.swift:252-262`): the only item mutator that no-ops an
  unchanged value (`:256`), the comment (`:251-254`) citing the spurious-LWW
  hazard of re-committing the same parse.
- **UI divergence**: title/description are `Binding<String>`s committing per
  keystroke (`ChecklistDetailView.swift:197-212`); relativeDate has no
  binding — a local draft buffer commits only when the parsed value
  changes (`:291-342`). All three go through the same store `scheduleSave`
  debounce and item-level stamping; all three leave the checklist's own
  `revision`/`modifiedAt` untouched.
- **Callers outside the view**: tests only (`ChecklistStoreTests.swift` and
  `ChecklistDetailViewTests.swift:57`).

## Cross-Cutting Observations

- **There is already a per-axis clock in the codebase**: order state
  (`orderRevision`/`orderModifiedAt`) is stamped and merged independently of
  the item's `revision`/`modifiedAt` (`ChecklistMerge.swift:93-110`,
  `ChecklistStore.swift:296-306`), and `moveItems` exists precisely because
  a reorder must not look like an item edit. Per-field text clocks would
  follow this established pattern.
- **The codec's extension mechanism is additive optional keys without a
  version bump**: `description` and `relativeDate` both shipped this way
  (`Checklist.swift:53-54`); decode defaults to `""`, `.distantPast`, `0`
  and `nil`. Adding per-field revision/date keys would not require a
  version bump under current conventions, though `classify` (which maps
  anyway) and the `.loaded` vs `.migratable` outcomes are version-switched.
- **The merge is a pure function with an exhaustive direct test suite** at
  `ChecklistMergeTests.swift` — behavioral changes to item conflict
  resolution land there first, before store/service layers.
- **Whole-item copy is only at the item level**: the checklist-level merge
  already copies selected fields (`:83-86`), and order is fully separate.
  `result[index] = remoteItem` (`:131`) is the single whole-record
  clobber point.
- **Tombstone revision is pinned to `removed.revision + 1`**: any design
  that changes what "one edit" means per field must keep a tombstone
  outranking every live revision of that item or it could resurrect deletes.
- **Existing tests already pin the clobber behavior** —
  `descriptionFollowsTheWholeItemLWinner` (`ChecklistMergeTests.swift:139`)
  asserts description follows the whole-item LWW winner; `sameItemEditedOnBothDevicesUsesLWW`
  (`:118`) pins whole-item LWW for a same-item conflict. Field-level merge
  will require updating these to the new semantics.
- **relativeDate's no-op guard is the model for per-field edit counting**:
  the store already refrains from stamping when a field value did not
  change, to avoid spurious LWW wins (`ChecklistStore.swift:252-256`);
  title/description currently always stamp.

## Open Areas

- Exact wire bytes of `ChecklistTombstone`'s synthesized codec (no explicit
  `CodingKeys`) — runtime-generated, only exercised via round-trip tests.
- Watch-side sync (`ChecklistSyncCoordinator`) encodes envelopes with
  `deviceID: ""`; how its two-way transport handles per-item state was not
  traced in this pass.
- The precise `ItemRow` TextField rendering below
  `ChecklistDetailView.swift:291` (draft-date plumbing verified, widget tree
  not).
- `ChecklistSyncService.reconcile`'s full in-flight coalescing semantics
  (`ChecklistSyncService.swift:62-73`) were summarized but not
  line-by-line traced — the observable contract (`readCount == 1` under
  concurrent refresh) is covered by `ChecklistSyncServiceTests.swift:204`.