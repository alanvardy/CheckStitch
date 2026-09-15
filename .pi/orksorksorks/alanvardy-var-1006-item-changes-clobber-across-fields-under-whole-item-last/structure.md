# Structure Outline

## Approach

Replace the whole-item LWW copy in `ChecklistMerge.mergedItems`
(`result[index] = remoteItem`) with a per-axis merge: each editable field
(`title`, `description`, `relativeDate`) gets its own `*Revision`/`*ModifiedAt`
clock, stamped only by its own mutator and resolved with the existing `wins`
comparator. The coarse item `revision`/`modifiedAt` is still bumped on every
edit and still decides the merged item's coarse clock, preserving the tombstone
invariant (`removed.revision + 1`). Six additive optional keys ride the current
v4 envelope; absent keys are seeded from the item's coarse clock on decode, so
legacy payloads keep today's semantics. No version bump, no migration phase.

Work is sliced by user-visible capability: title+description first (the ticket's
bug), then relativeDate (same plumbing, second capability), then hardening.

---

## Phase 1: Walking skeleton — concurrent title + description edits both survive

A title edit on one device and a description edit on another against the same
item both survive the merge, in either argument order, through the real
model → codec → merge → store → sync path. Green tests prove the reported
clobber is gone and that a legacy payload without the new keys still loads with
today's semantics.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitch/ChecklistMerge.swift`, `CheckStitch/ChecklistStore.swift`,
`CheckStitchTests/{ChecklistMergeTests,ChecklistCodecTests,ChecklistStoreTests,ChecklistSyncServiceTests}.swift`

**Key changes**:
- `ChecklistItem`: four new stored properties + coding keys —
  `var titleRevision: Int`, `var titleModifiedAt: Date`,
  `var descriptionRevision: Int`, `var descriptionModifiedAt: Date`.
  `init` gains them as trailing params defaulting to `nil`; when `nil` they
  seed from `modifiedAt`/`revision`, and `encode(to:)` writes all four
  unconditionally.
- `ChecklistItem.init(from:)` — `titleRevision = decodeIfPresent(...) ?? revision`
  and `titleModifiedAt = ... ?? modifiedAt`; mirror for description (design
  decision 3: a pre-upgrade record attributes its last whole-item edit to every
  field).
- `Checklist.migrated(at:)` — after stamping each item's `revision`/`modifiedAt`,
  set its title/description clocks to those same values.
- `ChecklistMerge`: private helper
  `fieldWins(_ revision: Int, _ date: Date, device: String, overRevision: Int, overDate: Date, overDevice: String) -> Bool`
  (thin wrapper over the existing `wins`); `mergedItems` starts from
  `localItem`, resolves `title` and `description` independently (copy remote
  value **and** clock on a win), then overwrites the coarse
  `revision`/`modifiedAt` with the whole-item winner's.
- `ChecklistStore`: `create`/`duplicate`/`addItem` seed the two clocks to the
  item's `now()`/`revision`; `updateItem(title:)` and
  `updateItemDescription(...)` set the matching field clock to the same new
  `revision`/`modifiedAt` they already stamp. Neither mutator touches the
  other field's clock.

**Contract** (consumed by Phase 2): a mergeable field is represented by the pair
`<field>Revision: Int` + `<field>ModifiedAt: Date`, seeded on decode from the
coarse clock, resolved by `wins(revision:date:device:overRevision:overDate:overDevice:)`
with remote as the candidate and device ids threaded from
`mergedItems(local:remote:localDevice:remoteDevice:)`. `mergedItems` remains the
only item resolution point; the merged item's coarse clock always comes from the
whole-item winner.

**Tests** (`make test-unit`):
- `ChecklistMergeTests` (Swift Testing) — replace
  `sameItemEditedOnBothDevicesUsesLWW` and `descriptionFollowsTheWholeItemLWinner`
  with `titleAndDescriptionEditsOnDifferentDevicesBothSurvive` and its
  reversed-argument-order twin; assert the losing field's clock is preserved on
  the merged item (a third merge is a no-op) and that a tombstone still beats a
  newer field clock.
- `ChecklistCodecTests` (XCTest) — round-trip preserves all four keys; a raw
  JSON item without them seeds each clock from `revision`/`modifiedAt`; v1/v2/v3
  classification unchanged.
- `ChecklistStoreTests` (XCTest) — a title edit bumps `titleRevision` + coarse
  revision and leaves `descriptionRevision` untouched (mirror for description);
  create/duplicate/addItem seed both clocks; v1 `migrated(at:)` seeds them;
  tombstone revision is still `removed.revision + 1`.
- `ChecklistSyncServiceTests` (Swift Testing) — concurrent title+description
  edits reconcile, and the pushed bytes decode with both values intact.

**Verify**: `make test-unit` green for the four suites; then `./scripts/test.sh`
prints `gate: ok`. Manual check: two simulators/devices, edit title on one and
description on the other, sync, confirm both.

---

## Phase 2: Concurrent relative-date and text edits both survive

Extends the same per-axis merge to the third field: a relative-date change on
one device and a text edit on another both survive, and re-committing an
unchanged date still stamps nothing.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitch/ChecklistMerge.swift`, `CheckStitch/ChecklistStore.swift`,
`CheckStitchTests/{ChecklistMergeTests,ChecklistCodecTests,ChecklistStoreTests}.swift`

**Key changes**:
- `ChecklistItem`: `var relativeDateRevision: Int`, `var relativeDateModifiedAt: Date`,
  two coding keys, decode-seed from the coarse clock, encode always.
- `Checklist.migrated(at:)` and `ChecklistStore`'s create/duplicate/addItem seed
  the relativeDate clock alongside the other two.
- `ChecklistMerge.mergedItems`: third independent field block for `relativeDate`
  (value and clock copied on a `fieldWins` win).
- `ChecklistStore.updateItem(checklistID:itemID:relativeDate:)` — keep the
  existing unchanged-value guard; when it does change, set the relativeDate
  clock to the new coarse `revision`/`modifiedAt`.

**Contract**: the three-field clock set is now complete and is the frozen item
merge contract; Phase 3 adds no new keys.

**Tests** (`make test-unit`): `ChecklistMergeTests` —
`relativeDateAndTitleEditsOnDifferentDevicesBothSurvive` in both argument
orders; `ChecklistCodecTests` — round-trip preserves all six keys and legacy
seed covers the date field; `ChecklistStoreTests` — an unchanged
`relativeDate` is a no-op for every clock, a changed one stamps
`relativeDateRevision` + coarse only, and `moveItems` still leaves all clocks
untouched.

**Verify**: `make test-unit` green; then `./scripts/test.sh` prints `gate: ok`.

---

## Phase 3: Hardening — mixed-version fixtures, churn, watch transport

Close the risks the design flagged: legacy/mixed fixtures must not spuriously
reassign fields, clock-only differences must not cause unbounded push-back, and
per-field clocks must survive the watch context transport (`deviceID: ""`).

**Files**: `CheckStitchTests/{ChecklistMergeTests,ChecklistSyncServiceTests,ChecklistSyncCoordinatorTests,WatchChecklistStoreTests}.swift`
(implementation changes only if a test exposes a defect)

**Key changes**: no new wire keys; possibly a targeted tweak to
`contentEquals`/the `merged != envelope` push guard if the churn test shows a
clock-only write loop (design open risk), and a device-id fallback decision if
the watch transport drops the field tie-break.

**Contract**: unchanged from Phase 2 — this slice only pins behaviour.

**Tests** (`make test-unit`):
- Mixed fixture: a v3/v4 item without field keys merged with a post-upgrade
  single-field edit yields exactly one winning field and keeps the untouched
  field's seeded value.
- Idempotence: merge → push → re-read produces no additional write pass
  (`ChecklistSyncServiceTests` push-back assertions hold with the six clocks
  present).
- Watch/coordinator: a per-field merge survives
  `ChecklistSyncCoordinator` encode/transport with `deviceID: ""` and the
  tie-break still resolves deterministically.

**Verify**: `make test-unit` green; then the full gate `./scripts/test.sh`
prints `gate: ok` (includes `make watch-build`).

---

## Testing Checkpoints

- After Phase 1: merge/codec/store/sync-service suites green under `make test-unit` — do not start Phase 2 otherwise.
- After Phase 2: all six clocks covered in codec + merge + store suites — frozen wire contract.
- After Phase 3: full gate `./scripts/test.sh` prints `gate: ok`, including the watch compile leg.