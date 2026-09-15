# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| —     | e820c2b | research: VAR-1006 merge conflict decomposition, findings, conventions |
| —     | d83c46f | chore: drop DELETEME placeholder |
| 1     | f159201 | Phase 1: per-field title/description clocks resolve concurrent edits (VAR-1006) |
| 2     | 1f1bb53 | Phase 2: concurrent relative-date and text edits both survive (VAR-1006) |
| 3     | c5c5b57 | Phase 3: hardening tests for mixed fixtures, push churn, watch transport (VAR-1006) |

## Automated Checks

- [x] Phase 1: `make test-unit` passes (merge + codec + store + sync-service suites green)
- [x] Phase 2: `make test-unit` passes (all six clocks covered by codec + merge + store)
- [x] Phase 3: `make test-unit` passes (merge + service + coordinator + watch suites)
- [x] `./scripts/test.sh` prints `gate: ok` — run once by the parent on the final
      tree after all three phases committed (covers all three per-phase gate items
      and the after-Phase-3 checkpoint, including `make watch-build`)

## Manual Verification Items (from the plan)

- [ ] **Phase 1** — Two simulators (or a phone + simulator) signed into the same
      iCloud account: baseline the item on both, edit only the title on device A
      and only the description on device B, force a sync, and confirm each device
      ends with both edits.
- [ ] **Phase 2** — Two devices: set a relative date on one and edit the title on
      the other; after sync both edits are present, and opening/re-committing the
      date picker without changing the value causes no further write.
- [ ] **Phase 3** — Install a fresh old-version build and a new build on two
      devices sharing the same App Group: create an item on the old build, edit it
      on the new build, sync both ways, and confirm the untouched field is not
      reassigned.
- [ ] **Phase 3** — Watch: edit an item on the phone, confirm the watch context
      still shows title/description/date and that a date change on the phone
      reaches it.

## Notes for Review

- **Plan 3.5 interpretation (flag)**: `emptyDeviceIDsResolvePerFieldDeterministically`
  as literally worded ("merge in both argument orders and assert checklists are
  equal") is unsatisfiable — with equal clocks, empty device ids and differing
  inputs, neither order grants a win, so each order reproduces its *own* input and
  the two outputs necessarily differ. Implemented the meaningful reading: no axis
  wins without a device id; each argument order reproduces its own local input
  exactly (no spurious reassignment), asserted for both orders.
- **Intent-preserving deviations in Phase 1** (worker-flagged, all deterministic):
  the plan's sync-test snippet omitted explicit title clocks on the remote item,
  which seeds them from the coarse revision and would fail the plan's own
  `title == "A title"` assertion — the remote's title clock is set to the pre-edit
  baseline instead. The plan's snippet also listed `revision` before `modifiedAt`
  in the initializer call (Swift requires `modifiedAt` first) — reordered.
- **No implementation changes were needed in Phase 3** — all five hardening tests
  passed against the Phase 1/2 code; the "If a test exposes a defect" branches
  were never hit (no push churn, no clock drops on watch/coordinator transport).
- **Environment flake**: one transient `CopySwiftLibs … No such file or directory`
  failure observed during a Phase 1 `make test-unit` re-run (incremental-build
  flake; subsequent runs clean). Not code-related; may reappear under concurrent
  build load on this machine.
- Wire format: no version bump — `currentVersion` stays 4; the six new keys are
  additive optionals that seed from the item's coarse clock on decode, so legacy
  payloads keep today's semantics on first contact. Watch/coordinator transport
  round-trips all six clocks unchanged.