# Design Discussion

## Current State

CheckStitch persists checklists locally and syncs them through iCloud KVS. The
seams this feature must reuse already exist:

- **Codec** — `ChecklistCodec` (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:310-338`)
  probes only the `version` key (`VersionProbe`, :348) and returns
  `.loaded` / `.migratable(from:envelope:)` / `.unsupportedVersion` /
  `.unreadable`. `encode` (:304-306) is `JSONEncoder().encode(envelope)`, so a
  codec payload *is* JSON text. `ChecklistEnvelope` (:238) is
  `version/deviceID/checklists/tombstones`; the decoder defaults
  `deviceID`/`checklists`/`tombstones` via `decodeIfPresent` (:255-264), so a
  minimal payload decodes cleanly.
- **Store** — `ChecklistStore` (`CheckStitch/ChecklistStore.swift`) is the only
  encoder: `var envelope` (:100-105) builds the canonical envelope. Every
  mutation ends in `save()` (:365-377) or coalesced `scheduleSave()` (:346-356);
  `save()` calls `onChange?()` unless `isApplyingRemote`.
  - `sameName` (:212-215) is trimmed + case-insensitive — the conflict primitive.
  - `uniqueName(basedOn:taken:)` (:191-197) produces `"Groceries 2"`.
  - `delete(id:)` (:308-315) appends a whole-checklist tombstone
    (`itemID: nil`, `revision + 1`).
  - `create(name:)` (:127-136) always disambiguates the name and appends.
  - `duplicate(id:name:)` (:143-156) is the fresh-identity precedent: new item
    UUIDs, `revision: 1`, name disambiguated.
  - `apply(remote:)` (:320-338) merges via `ChecklistMerge` (LWW), guards
    `canOverwriteStoredPayload` and current version, and suppresses `onChange`.
- **Sync** — `ChecklistSyncService.start()` (`ChecklistSyncService.swift:44-50`)
  wires `store.onChange -> schedulePush()` and
  `sync.startObserving -> reconcile()`. A store mutation therefore pushes
  automatically: `save()` -> `onChange` -> `pushNow()` -> `reconcileNow()`
  (:102-171) -> `contentEquals` differs (tombstones included) -> `sync.write`.
- **UI** — `ContentView.swift` owns the sole list screen. Rows are
  `NavigationLink` tap-to-navigate (`checklistRow(for:)` :262); navigation state
  is a `[UUID]` path stack; macOS actions are `.toolbar` items (:56-63), iOS
  actions are floating `CardPlate` overlays. **No selection state exists.**
  `ChecklistDetailView.swift` holds the only confirm patterns:
  `confirmationDialog` + presented flag for delete, drafted-name alert for
  duplicate/rename.
- **File APIs** — nothing in this repo or `/Users/vardy/dev/SingleThread` uses
  `.fileExporter` / `.fileImporter` / `ShareLink`; the API names in `task.md`
  are requirements, not precedent. Platform availability/entitlement details
  came from web sources (see research Q5).

Research gaps that shaped the questions below: whether `apply(remote:)` or
direct mutations is the ingestion path for imported payloads, and whether the
macOS export panel needs `com.apple.security.files.user-selected.read-write`.

## Desired End State

The user can export any subset of checklists to a `CheckStitch-<date>.json`
document, and import such a document back — on the same device or another —
with a per-conflict choice and no silent data loss.

Correctness criteria:

1. Export of selection S produces a payload that `ChecklistCodec.classify`
   returns as `.loaded`, and decoding it yields exactly S (names, items,
   `itemOrder`, `relativeDate`).
2. An unsupported version or an unreadable file shows an error alert and
   mutates nothing.
3. A name conflict (via `sameName`) never overwrites without an explicit
   user choice.
4. Every applied replace records a tombstone and pushes through
   `ChecklistSyncService` with no extra wiring.
5. Importing the same file twice is stable — no duplicate/dropped data beyond
   what the user chose.

## Patterns to Follow

**Follow:**

- `ChecklistStore.envelope` (`ChecklistStore.swift:100-105`) — build the export
  envelope the same shape, with `version: ChecklistCodec.currentVersion`.
- `delete(id:)` + `duplicate(id:name:)` (`ChecklistStore.swift:308-315`,
  :130-149) — the replace path must mirror delete's tombstone shape and
  duplicate's fresh-identity/revision-1 semantics.
- `ContentUnavailableView`/`.alert` and the detail view's
  `confirmationDialog` + presented-flag pattern (`ChecklistDetailView.swift`,
  delete flow) for the conflict prompts.
- Codec outcome handling exactly as each existing consumer does: distinguish
  `.unsupportedVersion` (refuse, preserve) from `.unreadable` (refuse) —
  `ChecklistStore.swift:67-97`, `ChecklistSyncService.swift:123-150`.
- Test style: XCTest `@MainActor` classes with `guard case ... else { XCTFail }`
  for outcome matching and `XCTUnwrap` for decode (`ChecklistCodecTests.swift:33-35,115`);
  Swift Testing structs with `#expect(..., "message")` for behavior
  (`ChecklistSyncServiceTests.swift:40-46`). Fakes belong in
  `CheckStitchTests/TestFixtures.swift`.
- New files under `CheckStitch/` need no `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`).

**Do NOT follow:**

- `apply(remote:)` as the import ingestion path — its merge silently resolves
  conflicts by LWW, which would override the user's explicit replace/keep.
- `create(name:)` as the insert primitive — it always renames via
  `uniqueName` (`ChecklistStore.swift:127-136`), losing the imported name and
  making "replace" produce `"Groceries 2"`.
- `store.envelope` reuse for export — it carries *all* checklists, all
  tombstones and the local `deviceID`; export needs a filtered envelope.

## Design Decisions

1. **Export payload: selected checklists only, `deviceID: ""`, `tombstones: []`.**
   A document, not a backup. Prevents resurrecting deletions and avoids foreign
   deviceIDs entering LWW tie-breaks; the decoder already tolerates the empty
   defaults (`Checklist.swift:255-264`).
2. **Import ingestion: new explicit store primitives, not `apply(remote:)`.**
   Add `importInsert(_ checklist: Checklist)` and `importReplace(id: UUID, with: Checklist)`
   (naming TBD at plan time) to `ChecklistStore`. Both `save()`; `importReplace`
   calls the same tombstone append as `delete(id:)` before inserting. The
   user's per-conflict choice is the conflict resolution — the merge engine
   must not get a second, invisible vote.
3. **Replace uses fresh local identity.** Tombstone the local checklist
   (`itemID: nil`, `revision + 1`), insert imported content with new UUIDs,
   `revision: 1`, `modifiedAt: now()`. Follows `duplicate`'s precedent, avoids
   shared IDs across devices after importing the same file twice.
4. **Keep Both inserts under a disambiguated name** via `uniqueName` — the
   non-destructive third option in the conflict dialog.
5. **Multi-select lives in a dedicated Export sheet**, opened from the macOS
   toolbar and an iOS floating overlay (or toolbar). The main list stays
   tap-to-navigate; no `EditMode` retrofit.
6. **Export mechanism: `.fileExporter` on the root view** with an in-memory
   `FileDocument` / `Transferable` carrying the encoded bytes and
   `defaultFilename: "CheckStitch-<yyyy-MM-dd>"`. `ShareLink` is added only if
   it is a small increment afterward.
7. **Errors are blocking and pre-mutation.** `.unreadable` → "This file isn't a
   CheckStitch export."; `.unsupportedVersion` → "created by a newer version".
   Nothing is written in either case, matching every existing consumer.
8. **Conflicts prompt sequentially**, one `confirmationDialog` per conflicting
   checklist with Replace / Keep Both / Keep Existing — never an automatic
   overwrite.
9. **No `deviceID` stamping on insert.** Imported checklists are local objects;
   `deviceID` stays the store's. (Exports carry `""` anyway.)

## What We're NOT Doing

- No whole-library export / backup / restore mode.
- No import of tombstones or `deviceID` — neither is honoured on the way in.
- No `apply(remote:)` reuse, no changes to `ChecklistMerge` or the merge engine.
- No `List`/`NavigationLink` restructuring and no `EditMode` multi-select.
- No changes to the codec format, `currentVersion`, or migration paths.
- No new App Group entitlement unless the macOS export panel demonstrably
  requires `com.apple.security.files.user-selected.read-write`.
- No drag-and-drop, no clipboard/`UIPasteboard`, no AirDrop-specific code
  beyond what `ShareLink`/`fileExporter` give free.
- No watchOS surface for import/export.
- No child Linear tickets — all work lands on the single ticket/VAR-997.

## Open Risks

- **`FileDocument` vs `Transferable` variant:** the exact `.fileExporter`
  signature for this toolchain (iOS 27 / Xcode 26.6) is unverified in-repo;
  the `Transferable` variant has a different overload. Confirm during
  implementation and keep the encoding step identical either way.
- **macOS sandbox:** the developer-signed macOS app may block the save/open
  panel without `com.apple.security.files.user-selected.read-write` in
  `CheckStitch/AppGroup.entitlements`. `make build-mac` is unsigned so the
  gate will not catch it; verify with `make build-mac-signed` before claiming
  done.
- **`.fileImporter` security scope:** returned URLs need
  `startAccessingSecurityScopedResource()` / `stop...` around the read; a
  missing pair silently yields unreadable data on device — test on a real
  device or watch for it in the failure path.
- **Attachment point:** attaching `.fileExporter` inside the sheet/popover
  breaks the macOS panel; it must be on the root view.
- **Import-and-sync interaction is untested today:** no existing test pushes a
  delete/tombstone end-to-end through sync (research Q3/US). The replace path's
  "tombstone recorded and pushed" claim rests on the `save → onChange →
  schedulePush` chain, so our tests should assert the tombstone *and* the
  `onChange`-driven push, not just the tombstone.
- **Where import lands:** with fresh identities and `revision: 1`, an imported
  checklist may lose an LWW race with a same-ID remote copy on another device
  — expected given decision 3, but worth an explicit test expectation.

## Verification

- Fast loop: `make test-unit` (codec round trip, store import primitives,
  conflict replace/skip, bad-payload rejection).
- Full gate: `bash scripts/test.sh` must print `gate: ok`.
- Signed macOS check for the export/import panel: `make build-mac-signed`.