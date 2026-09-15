# Design Discussion

## Current State

- `ChecklistMerge.mergedItems` resolves a same-id item conflict with
  `result[index] = remoteItem` (`ChecklistMerge.swift:131`) — the entire
  `ChecklistItem` is replaced by whichever whole record wins the coarse clock
  (`wins`, `ChecklistMerge.swift:166-171`: revision, then date, then smaller
  device id). This is the single whole-record clobber point; checklist level
  already copies selected fields (`:83-86`) and ordering has its own clock
  (`orderRevision`/`orderModifiedAt`, `:93-110`).
- An item now has three independently editable fields: `title`,
  `description` (VAR-999) and `relativeDate` (`Checklist.swift:22-26`). Only
  item-level `revision`/`modifiedAt` exist (`Checklist.swift:19-20`), and all
  three store mutators bump them — title/description unconditionally
  (`ChecklistStore.swift:225-250`), relativeDate only on an actual change
  (`:252-256`).
- Consequence: a title edit on device A and a description edit on device B
  against the same item are treated as one conflict. The higher revision wins
  and replaces the whole item, silently discarding the other field's edit.
- The codec is a versioned envelope (`currentVersion = 4`,
  `Checklist.swift:283`) whose extension mechanism is *additive optional keys
  without a version bump* — `description` and `relativeDate` both shipped this
  way and absent keys fall back to defaults (`Checklist.swift:53-54, :47-55`).
  `classify` (`:310-338`) probes only the `version` key.
- Tombstones are append-only and outrank live records because a tombstone's
  `revision` is always `removed.revision + 1` (`ChecklistStore.swift:263`),
  so a delete can never be resurrected (`ChecklistMerge.swift:7-9, :50-52`).
  Any change to what "one edit" means must preserve this invariant.
- There is already a per-axis clock precedent in the codebase: order state is
  stamped and merged independently so a reorder is never mistaken for an item
  edit (`ChecklistStore.swift:296-306`, `ChecklistMerge.swift:93-110`).
- The merge is a pure function with a direct Swift Testing suite; two existing
  tests pin the behavior being removed: `sameItemEditedOnBothDevicesUsesLWW`
  (`ChecklistMergeTests.swift:118`) and `descriptionFollowsTheWholeItemLWinner`
  (`:139`).

## Desired End State

Two devices that each edit a different field of the same item both keep their
edit after sync, regardless of which coarse item revision is higher.

- A concurrent title edit (device A) and description edit (device B) merge to
  `title = A's`, `description = B's`.
- A concurrent `relativeDate` edit and *any* other field edit likewise both
  survive.
- Deletion is unchanged: a tombstoned item stays deleted no matter how many
  field edits exist on either side.
- Re-merging a merged payload is a no-op (`contentEquals` idempotence,
  `Checklist.swift:277-278`), and both merge argument orders produce the same
  result (symmetric `wins`).
- Legacy payloads (v1–v4, no per-field keys) load and merge with exactly
  today's semantics on first contact — no field is spuriously reassigned.

Verification: `make test-unit` then the full gate `./scripts/test.sh`
(`conventions.md`); new merge tests cover concurrent title+description and
title+relativeDate edits from two devices in both argument orders.

## Patterns to Follow

- **Per-axis clocks** — copy the order-state pattern: an independently stamped
  `*Revision`/`*ModifiedAt` pair per mergeable axis, resolved by the same
  comparator (`ChecklistMerge.swift:93-98`, `ChecklistStore.swift:296-306`).
- **Additive optional keys, no version bump** — mirror `description`'s
  decode-default/encode-always mechanics (`Checklist.swift:47-79`); old peers
  ignore unknown keys, `classify` is untouched.
- **Store is the only encoder**, `save()` refuses while
  `canOverwriteStoredPayload == false` (`ChecklistStore.swift:103-105, :370`).
- **Injectable time and fixed literals** — store tests use the `Clock`
  (`ChecklistStoreTests.swift:39`); merge/codec/service fixtures use
  `Date(timeIntervalSince1970:)` literals. No test yields to a live clock.
- **Behavioral merge changes land in `ChecklistMergeTests` first**, before
  store/service layers (`research.md` cross-cutting observation).
- **Swift Testing structs + `@MainActor`** for new unit tests; XCTest only for
  store/codec suites (AGENTS.md, `conventions.md`).
- **Do NOT follow**: the whole-item LWW copy at `ChecklistMerge.swift:131`, and
  do not add a no-op guard to `title`/`description` — keystroke coalescing via
  the 300 ms `scheduleSave` debounce (`ChecklistStore.swift:351-363`) is the
  accepted mechanism, and a guard would drop legitimate re-commits.
- **Do NOT follow**: a version bump plus `.migratable` path — the repository's
  explicit convention is additive keys without one, and a v5 bump would make
  every v4 peer read-only (`ChecklistStore.swift:92`).

## Design Decisions

1. **Field coverage**: title, description **and** relativeDate get per-field
   clocks. The bug class is identical for the date field, the plumbing is the
   same code path, and special-casing two of three fields would leave a known
   clobber. Slightly wider than the ticket's text-field wording; agreed with
   the operator.

2. **Wire format**: six new additive optional keys on `ChecklistItem` —
   `titleRevision`, `titleModifiedAt`, `descriptionRevision`,
   `descriptionModifiedAt`, `relativeDateRevision`, `relativeDateModifiedAt`.
   Encoded always; decoded with `decodeIfPresent`. No `currentVersion` change,
   no `classify` change.

3. **Backfill on decode**: when a field clock key is absent, seed it from the
   item's own `revision`/`modifiedAt` (`titleRevision ?? revision`, etc.), so a
   pre-upgrade record attributes its last whole-item edit to every field. This
   reproduces today's semantics on first post-upgrade sync and avoids a
   spurious field winner.

4. **Coarse item clock retained**: `revision`/`modifiedAt` continue to be
   bumped on *every* item edit exactly as today, in parallel with the new
   field clocks. This keeps the tombstone invariant (`removed.revision + 1`)
   and keeps mixed-version peers behaving as before. On merge, the merged
   item's coarse `revision`/`modifiedAt` are taken from the whole-item winner,
   while each field's value and clock are resolved independently.

5. **Merge rule for a same-id item**: start from the local item; for each of
   the three fields, if the remote field's `(revision, modifiedAt)` wins via
   the existing comparator (device id tie-break included), copy the remote
   value *and* its clock; then overwrite the coarse `revision`/`modifiedAt`
   with the whole-item winner's. Timer: pass `localDevice`/`remoteDevice` into
   the field comparison exactly as `mergedItems` already does
   (`ChecklistMerge.swift:116-135`). Tombstone union/suppression and order
   merge are untouched.

6. **Stamping discipline**:
   - create/addItem/duplicate: new item gets `revision: 1`, `modifiedAt: now()`
     and **all three field clocks seeded to those same values** (a fresh record
     has no divergent field history).
   - `migrated(at:)` (`Checklist.swift:160-176`): after stamping item
     `revision`/`modifiedAt`, stamp all three field clocks to the same values.
   - title/description edits: bump the item clock as today, then set the
     matching field clock to the new `revision`/`modifiedAt`.
   - relativeDate: keep the unchanged-value guard (`ChecklistStore.swift:256`);
     when it does change, bump the item clock and set the relativeDate field
     clock.
   - No store mutation writes fields *other than* the one being edited.

7. **Tests to add/replace**:
   - `ChecklistMergeTests` (Swift Testing): title-on-A + description-on-B
     survives in **both** argument orders; title + relativeDate likewise;
     losing field's clock is preserved on the merged result (so a third merge
     is still a no-op); tombstone still beats a newer field clock. Replace
     `sameItemEditedOnBothDevicesUsesLWW` and
     `descriptionFollowsTheWholeItemLWinner` with the new semantics.
   - `ChecklistCodecTests` (XCTest): round-trip preserves all six keys; a
     payload without the keys seeds each field clock from
     `revision`/`modifiedAt`; v1/v2/v3 classification unchanged.
   - `ChecklistStoreTests` (XCTest): a title edit bumps `titleRevision` +
     coarse revision and leaves `descriptionRevision` untouched; the mirror for
     description; an unchanged relativeDate is a no-op for every clock;
     create/duplicate/addItem seed all three clocks; tombstone revision is
     still `removed.revision + 1`.
   - `ChecklistSyncServiceTests`: concurrent title+description edits merge and
     the pushed bytes decode with both values intact.

## What We're NOT Doing

- No `currentVersion` bump, no new `classify` outcome, no `.migratable` path.
- No tombstone redesign, compaction, or change to `removed.revision + 1`.
- No change to checklist-level `name`/`destinationListIdentifier` LWW.
- No change to order merge, `moveItems`, or `reconciledOrder`.
- No UI, binding, debounce or EventKit/Reminders changes.
- No generic/dynamic field map: three explicit field pairs, not a dictionary.
- No change to what counts as an edit for title/description (no new no-op
  guards); debounce coalescing is unchanged.
- No child tickets; all work lands on the main ticket.

## Open Risks

- **Mixed-version peers**: a v4 peer runs whole-item LWW with the coarse clock.
  Because we keep bumping that clock, its edits still win/lose as before and can
  overwrite a new-version field edit. This is accepted graceful degradation,
  not data corruption; it stops once every device upgrades.
- **Equality/push churn**: the synthesized `Hashable`/`Equatable` on
  `ChecklistItem` now includes the six clocks, so `contentEquals`
  (`Checklist.swift:277-278`) and the `merged != envelope` guard
  (`ChecklistStore.swift:330`) can observe clock-only differences and trigger a
  push-back. Benign, but watch the sync-service idempotence tests for extra
  write passes.
- **Decode-seeding symmetry**: if only one side upgrades first, both sides put
  the same seeded clocks on an untouched item, so a post-upgrade single-field
  edit still produces a single winning field — verify with a mixed-fixture
  merge test.
- **relativeDate widens scope** beyond the ticket's two text fields; the extra
  surface is one store mutator and its tests.
- **Watch path**: `ChecklistSyncCoordinator` encodes envelopes with
  `deviceID: ""` (`research.md` open area); confirm per-field clocks survive
  the watch context transport rather than assuming it, since device id is the
  `wins` tie-break.