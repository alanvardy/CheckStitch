# Structure Outline

## Approach

Make ordering a first-class, independently-stamped piece of mergeable state:
add `itemOrder: [UUID]` + `orderRevision`/`orderModifiedAt` to `Checklist`,
bump the codec to v3 with a v2→v3 migration, reconcile order in
`ChecklistMerge` via the existing `wins` tiebreak, expose
`ChecklistStore.moveItems(checklistID:from:to:)` (silent no-op on bad input),
and wire it to `.onMove` + `EditButton`. Each layer is fully tested before the
next: **model/codec → merge → store → UI**.

---

## Stage 1: Model & Codec — `itemOrder` and the v3 migration

Adds the ordering fields and the one-way v2→v3 migration. Green tests prove
old v1/v2 payloads still load, v3 round-trips, and a decoded checklist's
`items`/`itemOrder` invariant holds.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitchTests/ChecklistCodecTests.swift`, `CheckStitchTests/ChecklistItemTests.swift`

**Key changes**:
- `Checklist { var itemOrder: [UUID]; var orderRevision: Int; var orderModifiedAt: Date }` — new stored properties
- `CodingKeys` += `itemOrder`, `orderRevision`, `orderModifiedAt`; `init(from:)` uses `decodeIfPresent` defaults (`itemOrder` derived, `0`, `.distantPast`); `encode` writes all three
- `ChecklistCodec.currentVersion = 3`; `classify` treats `1` and `2` as `.migratable(from:)`
- `Checklist.migrated(at:)` — derive `itemOrder = items.map(\.id)` when absent; seed `orderRevision = max(revision, 1)`, `orderModifiedAt = modifiedAt` (no spurious ordering win)
- `Checklist.normalizedOrder() -> Checklist` (internal) — canonicalize `items` to `itemOrder`, append any item id missing from it; the drift self-heal used on decode and by later layers

**Tests**: `ChecklistCodecTests` — v3 round-trip, v2→v3 migratable, v1→v3 migratable, >v3 still `.unsupportedVersion`; `ChecklistItemTests` — decode defaults + `normalizedOrder` happy path and missing-id-in-order sad path. Existing watch/coordinator suites (`WatchChecklistStoreTests`, `ChecklistSyncCoordinatorTests`) must stay green.

**Verify**: `make test-unit` passes for this stage.

---

## Stage 2: Merge — order reconciliation in `ChecklistMerge`

Teaches the pure merge to resolve *which* ordering wins and to emit a
deterministic, idempotent, symmetric result. Green tests prove convergence and
that a re-merge is a no-op (so `apply`'s `merged != envelope` guard holds).

**Files**: `CheckStitch/ChecklistMerge.swift`, `CheckStitchTests/ChecklistMergeTests.swift`

**Key changes**:
- `mergedChecklists(local:remote:)` — on order conflict copy winner's `itemOrder`/`orderRevision`/`orderModifiedAt`; winner via existing `wins(revision: orderRevision, date: orderModifiedAt, device: …)`
- New helper `reconciledOrder(winnerOrder: [UUID], mergedItems: [ChecklistItem], fallback: [UUID]) -> [UUID]` — winner ids that survive in merged items keep winner order; merged-item ids absent from winner order appended in `fallback` (local/merged) order; tombstones drop their ids
- `mergedItems` unchanged in membership (local-first, remote-only appended) but its output is re-sorted to `reconciledOrder` before return
- Result always wears `local.deviceID` (unchanged)

**Tests**: `ChecklistMergeTests` — order winner by revision/timestamp/device, remote-only item appended **and** order winner together, tombstoned id excluded, **symmetry** (both argument orders equal), idempotence (re-merge == merge), identical-envelope no-op. Fixture builders extended with order stamp args.

**Verify**: `make test-unit` passes for this stage; both-arg-order symmetry asserted in the merge suite.

---

## Stage 3: Store — `moveItems` and the order invariant

Adds the public mutation, keeps `items`/`itemOrder` in lockstep on every
existing path, and persists immediately (structural edit, not a text edit).
Green tests prove move semantics, identity preservation, and reload survival.

**Files**: `CheckStitch/ChecklistStore.swift`, `CheckStitchTests/ChecklistStoreTests.swift`

**Key changes**:
- `moveItems(checklistID: UUID, from: IndexSet, to: Int)` — new; unknown id / out-of-range `from` or `to` → silent no-op; reorder `items` and `itemOrder` identically with explicit `move(fromOffsets:toOffset:)` arithmetic; `orderRevision += 1`, `orderModifiedAt = now()`, immediate `save()` (cancels queued text save, no per-item stamp)
- `addItem(to:)` — append the new id to `itemOrder`
- `removeItems(from:at:)` — remove the deleted ids from `itemOrder`
- `apply(remote:)` — call `normalizedOrder()` on merged checklists after `ChecklistMerge.merge` (post-merge self-heal); no new stamps

**Tests**: `ChecklistStoreTests` — move within list, move to end, out-of-range `IndexSet`/`to`, unknown checklist id, identity preservation (`id`/`title`/`modifiedAt`/`revision` byte-identical), persistence across reload on the shared defaults, `items`/`itemOrder` invariant after add/remove/apply. Existing debounce/stamp/apply suites stay green.

**Verify**: `make test-unit` for this stage, then `bash scripts/test.sh` prints `gate: ok` before the UI layer.

---

## Stage 4: UI — `.onMove` + `EditButton`

Wires the proven store mutation to the drag affordance. This is the only layer
not fully unit-testable (drag delivery is framework-driven), so it is checked
by a render test plus a manual simulator pass.

**Files**: `CheckStitch/ChecklistDetailView.swift`, `CheckStitchTests/ViewRenderTests.swift`

**Key changes**:
- Items `ForEach` gains `.onMove { store.moveItems(checklistID: checklistID, from: $0, to: $1) }` alongside the existing `.onDelete`; explicit `id: \.id` if the render/behaviour check shows it is required
- Toolbar gains `EditButton()` so rows expose drag handles / become movable
- No new view state; mutation still routes through the store

**Tests**: `ViewRenderTests` — detail view renders with an empty and non-empty checklist; UI smoke (`make test-ui`) unchanged and green. **Manual**: `make run`, enter edit mode, drag a row, confirm order persists on relaunch.

**Verify**: `bash scripts/test.sh` prints `gate: ok`; manual simulator check of drag + macOS `Form`/`EditButton` handles (gate's `make build-mac` only compiles).

---

## Testing Checkpoints

- **After Stage 1**: `make test-unit` green — v1/v2 payloads migrate, v3 round-trips, invariant normalizer covered.
- **After Stage 2**: `make test-unit` green — merge order is symmetric, deterministic, idempotent.
- **After Stage 3**: `bash scripts/test.sh` → `gate: ok` — move semantics, identity preservation, reload, and sync-safe merge all proven.
- **After Stage 4**: `gate: ok` + manual drag check — the only framework-driven behaviour not covered by unit tests.

**Cross-cutting note**: drag delivery and macOS `EditButton`/`Form` handle
rendering cannot be exercised below the UI layer. The store mutation is stubbed
and fully proven in Stage 3; Stage 4 adds only the wiring and a manual check.
The mixed-version risk (older v2 build refuses a v3 payload) is an accepted
consequence of the v3 bump, not a separate layer.
