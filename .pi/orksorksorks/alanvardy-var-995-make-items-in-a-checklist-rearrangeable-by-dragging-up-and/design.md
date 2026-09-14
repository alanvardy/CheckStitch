# Design Discussion

## Current State

- The edit screen is `ChecklistDetailView` (`CheckStitch/ChecklistDetailView.swift`): a `Form` → `Section("Items")` → `ForEach(checklist.items) { TextField(...) }` (28-29) with `.onDelete` → `store.removeItems(from:at:)` (30-33). The `ForEach` passes no explicit `id:`; identity comes from `ChecklistItem: Identifiable`. There is **no** `onMove`/drag precedent anywhere in the repo (`research.md` Q6).
- The store is the single choke point (`CheckStitch/ChecklistStore.swift`): `@Observable final class ChecklistStore` (7), `private(set) checklists` (16), all mutations through public methods. Existing item methods: `addItem(to:)` (154-158, immediate `save()`), `updateItem(checklistID:itemID:title:)` (160-168, `scheduleSave()` + stamps item `revision`/`modifiedAt`), `removeItems(from:at:)` (170-179, `IndexSet` descending iteration + `indices.contains` bounds guard, immediate `save()`). Unknown ids are silent no-ops.
- Item identity/dirty-marking is `modifiedAt`/`revision` only (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:14-19`); only `addItem`/`updateItem` stamp items (`ChecklistStore.swift:156, 164-166`). A reorder would be invisible to sync unless ordering becomes mergeable state.
- Merge (`CheckStitch/ChecklistMerge.swift`) inherits order, never merges it: `mergedChecklists` bases on local and appends remote-only (68-74); `mergedItems` same (99-114); on conflict only `name`/`revision`/`modifiedAt` transfer (78-85), and the winning item struct replaces the whole local item at its local index (108-111). Winner rule `wins` = revision → timestamp → deviceID (`116-122`), symmetric.
- `contentEquals` (`Checklist.swift:160-166`) and `apply`'s `visibleChanged` (`ChecklistStore.swift:201`) are **order-sensitive** over `checklists`/`items`. Research Q5 traces the resulting push-back churn: each device re-pushes its own ordering and never adopts the remote one.
- Codec: `currentVersion = 2` (169); `classify` (194-211) → `.loaded` / `.migratable(from: 1)` / `.unsupportedVersion` / `.unreadable`; missing fields decode via `decodeIfPresent` defaults (50-57, 142-149); `Checklist.migrated(at:)` (91-102) is the sole normalization point.
- Sync: `ChecklistSyncService.reconcileNow()` (86-142) applies then push-backs when `visibleChanged || !contentEquals` (137-140); `.migratable` is re-wrapped with `migrated(at: .distantPast)` (129-130).

## Desired End State

1. In `ChecklistDetailView`, an `EditButton` toggles edit mode and rows become draggable up/down. Dropping calls `store.moveItems(checklistID:from:to:)` with the standard `IndexSet`/`Int` pair.
2. A move reorders items, updates ordering state, and persists immediately — but leaves every item's `id`, `title`, `modifiedAt`, and `revision` byte-identical.
3. Ordering **syncs**: a reorder on one device converges on the others instead of being silently discarded and push-back-storming.
4. New tests cover move-within, move-to-end, out-of-range indices, unknown checklist id, identity preservation, persistence across reload, and order merge/conflict.

## Patterns to Follow

- **Structural mutation = immediate `save()`**, cancelling any debounced text save (`ChecklistStore.swift:236-251`, `239-240`); `moveItems` is structural, not a text edit. Do **not** route it through `scheduleSave()` (220-234).
- **Bounds-guarded `IndexSet` handling**, mirroring `removeItems` (`ChecklistStore.swift:172-173`): sort descending / validate `to`; out-of-range and unknown checklist id are silent no-ops (no throw, no stamp).
- **Stamp discipline**: only ordering stamps change. Reuse the existing `wins(revision:date:device:over:)` (`ChecklistMerge.swift:116-122`) shape for order conflicts rather than inventing a second tiebreak.
- **Deterministic merge output**: tombstones are sorted by key so re-merging is a no-op (`ChecklistMerge.swift:57-61`); the new order reconciliation must be equally deterministic and idempotent, or `apply`'s `merged != envelope` guard (`ChecklistStore.swift:200`) will loop.
- **Codec compatibility**: additive fields use `decodeIfPresent` with an in-code default, as `deviceID`/`tombstones` do (`Checklist.swift:142-149`); migration stays centralized in `Checklist.migrated(at:)` (91-102).
- **Tests**: fresh uniquely-named `UserDefaults` suite + `defer` cleanup and `textEditDelay: nil`, plus a reload store to assert persistence (`ChecklistStoreTests.swift:11-31, 28-42`); `IndexSet(integer:)` is the existing precedent (68, 399-400); Swift Testing fixture builders for merge (`ChecklistMergeTests.swift:161-181`); `@MainActor` on store/EventKit suites.
- **Do NOT follow**: the `Form`/`ForEach` currently in the detail view as a `List` reorder host without checking edit-mode behaviour on macOS — `Form` is `List`-backed on iOS but the drag-handle requirement differs by platform; verify rather than assume (`research.md` "Open Areas").

## Design Decisions

1. **Ordering syncs (Q1: A).** Local-only ordering would leave devices permanently disagreeing about order *and* churning the KVS push-back trace in research Q5. Since CheckStitch advertises iPhone/iPad/macOS sync, ordering is user intent and must converge.
2. **Ordering lives on `Checklist` as `itemOrder: [UUID]`, stamped by `orderRevision`/`orderModifiedAt` (Q2: A).** Per-item `sortOrder` was rejected because merge replaces the whole winning item struct (`ChecklistMerge.swift:108-111`), so a per-item order field would drag the winner's `title` with it and pit a reorder against a concurrent title edit. A checklist-level ordered id list is one atomic, independently-stamped unit: name/title conflict resolution is untouched, and item `revision`/`modifiedAt` are never implicated.
   - `itemOrder` is the **canonical** order; the `items` array is kept sorted to match it as an invariant (encoded order and array order never diverge). `addItem` appends the new id; `removeItems`/`delete` drop the ids.
   - Move: reorder `items` + `itemOrder` identically, `orderRevision += 1`, `orderModifiedAt = now()`, immediate `save()`. Item fields untouched.
   - Merge conflict for order uses `orderRevision` → `orderModifiedAt` → deviceID via the existing `wins` shape, then **reconciles**: winner's ids that survive in merged items keep winner order; any merged-item id missing from the winner order is appended in local/merged array order. Deterministic and idempotent.
3. **`moveItems` is a silent no-op on bad input (Q3: A).** Matches `removeItems`' guard and `addItem`/`updateItem`'s unknown-id behaviour; `.onMove` input is framework-driven and a return value has no consumer.
4. **Reorder mode via `EditButton` (Q4: A).** Add `.onMove { store.moveItems(...) }` to the items `ForEach` and an `EditButton` in the toolbar; this is the standard iOS idiom and pairs the drag handles with the existing `.onDelete`.
5. **`currentVersion = 3` with a real v2→v3 migration (Q5: B).** `classify` accepts `1` and `2` as `.migratable`; `Checklist.migrated(at:)` derives `itemOrder` from `items.map(\.id)` when absent and seeds `orderRevision`/`orderModifiedAt` from the checklist's own `revision`/`modifiedAt` so migration grants no spurious ordering win. Old (>v3) payloads still fail closed as today.
6. **`moveItems(checklistID:from:to:)` mirrors SwiftUI's `move(fromOffsets:toOffset:)` semantics exactly** (destination is an insertion index in the pre-move coordinate space). Implement the index arithmetic explicitly in the store; do not depend on a SwiftUI-only `MutableCollection` extension from `CheckStitchCore`.

## What We're NOT Doing

- No per-item `position`/`sortOrder` field, no field-level item merge.
- No change to `updateItem`/`addItem` stamping, tombstones, or the delete path.
- No multi-select drag, no drag between checklists, no animated reordering polish beyond what `.onMove` gives.
- No new store mutation outcome enum; no throwing API.
- No change to KVS key/transport (`ChecklistSyncing.swift`), push debounce, or reconcile coalescing.
- No dependency on a remote reorder beating a local *title* edit — the two are independent by design.
- No new child tickets; all work on the main ticket (VAR-995).

## Open Risks

- **Mixed app versions**: a v2 build reading a v3 payload classifies it `.unsupportedVersion` and refuses to save/sync (`ChecklistStore.swift` init branch, `ChecklistSyncService.swift:131-134`) — the accepted cost of Q5B. Until all devices update, an older device will look "stuck".
- **`items` array vs `itemOrder` drift**: any mutation path that touches `items` without updating `itemOrder` (including merge) breaks the invariant. A normalization step on decode and after merge should make drift self-healing; tests must assert it.
- **`.onMove`/`EditButton` on macOS**: no in-repo precedent; whether handles render in a `Form` on the macOS slice needs a manual check (gate's `make build-mac` only compiles, it does not exercise the UI).
- **Order reconciliation with tombstones and remote-only items**: untested corner — a remote-only item appended *and* an order winner must produce one stable result; symmetry (both argument orders) must be asserted.
- **`contentEquals` push-back**: once ordering merges, remote reorders set `visibleChanged = true` and stop the churn; if reconciliation is non-deterministic this regresses into a push loop instead.