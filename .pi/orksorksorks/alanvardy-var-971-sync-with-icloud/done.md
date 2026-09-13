# Done

- **Branch / head SHA**: `alanvardy-var-971-sync-with-icloud` @ `2490c9b`
  (review fixes) on top of `9316ad6`; DELETEME placeholder removed and step
  artifacts committed in `bae3c35`.
- **Mechanical checks**: `bash scripts/test.sh` → **`gate: ok`** (simulator
  build, `make test-unit` **86 tests / 19 suites passed**, one-shot iOS UI smoke
  on this worktree's `.simulator_id`, `make build-mac`, 12 shell tests). Only
  warnings are the pre-existing `MACOSX_DEPLOYMENT_TARGET 27.0` range warnings.
  No SwiftLint config in the repo.

## Review outcome

One bounded fresh-context reviewer covered concurrency/data-race safety, merge
correctness/tombstones/migration, crash & data-loss resistance, API/architecture,
and SwiftUI state. Verdict "OK with notes"; no P0 found by the reviewer, but the
parent scan elevated the seed path to a blocker.

**Blocker fixed (B1) — seed could clobber a populated cloud.**
`ChecklistSyncService.reconcileNow()` read KVS without ever synchronizing and
then wrote the local payload whenever it saw `nil`. On a fresh install whose KVS
had not pulled yet, that pushed an *empty* envelope that wins KVS
last-write-wins over real remote data. Fix: `syncOnLaunch()` now calls
`synchronize()` before the first read, the one-shot `didSeed` gate is gone, and
the `nil` branch only writes when the local payload is non-empty
(`ChecklistSyncService.swift:63-75, 103-116`). Regression tests:
`emptyCloudWithEmptyLocalIsNotSeeded` (empty local never pushed) and
`emptyCloudSeedsNonEmptyLocal` (non-empty local still seeds once).

**Fixes worth doing now, applied:**
- **F1 Empty-state refresh** — `.refreshable` moved to the root `Group` and
  `emptyState` wrapped in a `ScrollView`, so pull-to-refresh works on a fresh
  device with no local rows (`ContentView.swift:32-36, 67-72, 209-223`).
- **F2 `.unavailable` surfaced** — `SyncStatusView.message` now renders
  "iCloud unavailable" for `.unavailable` (read failure / newer-payload guard),
  matching the design's "failures are surfaced" (`ContentView.swift:315-326`).
- **F3 `pushNow()` doc reconciled** — `reconcileNow()` is synchronous on the
  main actor, so it cannot interleave with an in-flight pass; `pushNow()`
  deliberately bypasses the async coalescing gate to finish before suspension,
  and the merge's idempotence guard makes the extra pass harmless. The class and
  method docs now say this instead of claiming universal coalescing.
- **F4 Test coverage** — added the cloud-v1 `.migratable` service test
  (`cloudV1PayloadIsMigratedOnReconcile`), an `onChange` suppression test for
  `apply(remote:)` (`testOnChangeFiresForLocalSavesButNotWhenApplyingRemote`),
  a `.unavailable` render test, and an observer-cancel idempotency test.

**Optional items applied:**
- Documented `Checklist.modifiedAt`/`revision` as rename-only (items merge on
  their own stamps) and noted the unbounded tombstone growth with a
  follow-up-ticket pointer (`Checklist.swift`, `ChecklistStore.swift`).
- Reconciled `ChecklistCodec.Outcome.unreadable`'s doc with the service's
  refuse-to-overwrite behaviour; added a defensive note to `apply`'s version
  guard; marked the `#Preview` KVS construction as construction-only.
- Trailing newlines added to the files touched by this branch.

**Deferred (not applied, by design):**
- `apply()` save-failure divergence between memory and disk: pre-existing
  swallow pattern with a logged error; low probability, tracked as a follow-up.
- Tombstone compaction/GC: needs a design decision on when no device can hold a
  pre-delete revision; noted in code and below.

## Remaining manual items

- Two devices on the same iCloud account (pinned simulator + a physical device
  via `bash scripts/run-devices.sh`): create on A, background A, pull-to-refresh
  on B; then rename/delete on B and pull on A. Confirm the empty state's
  pull-to-refresh fetches the first remote checklist (F1).
- Confirm no Reminders are created or removed by any sync operation.
- With iCloud signed out, confirm the app still works. Note: the real
  `UbiquitousChecklistSync.read()` never throws, so a signed-out device reads
  `nil` and (with a non-empty local store) reports `.seeded`, not
  `.unavailable`; `.unavailable` is only reached via the newer-payload guard or
  a thrown read. A true iCloud-availability probe is out of scope for this
  ticket.
- Tombstone growth remains unbounded against the 1 MB KVS ceiling — schedule a
  compaction follow-up.
