# Done

- **Branch / head SHA**: `alanvardy-var-1006-item-changes-clobber-across-fields-under-whole-item-last` @ `90fa7b4cd1be23e9ca95d7057186bd440067e1a0`
  (source-fix commit; the marker commit that adds this file follows it on the same
  branch). Branch rebased cleanly, working tree clean, pushed to origin.
- **Mechanical checks**: `./scripts/test.sh` → **`gate: ok`** (simulator build,
  `make test`, `make build-mac`, `make watch-build`, shell tests 17/17 passed,
  `shellcheck`), re-run after the review fixes. `make test-unit` → 212 tests in
  30 suites passed. Only flag: the benign `appintentsmetadataprocessor … no
  AppIntents.framework dependency found` warning.
- **Review outcome**:
  - **Blockers: none.** One bounded fresh-context `reviewer` and an independent
    parent scan both cleared the merge. Parent verified the load-bearing
    invariant directly: every write path stamps each field clock to the
    *post-bump* coarse revision (`ChecklistStore.swift:231/247/265`) and decode
    seeds field clocks from the coarse clock (`Checklist.swift:79-86`), so
    `fieldRevision <= revision` always; because the coarse winner's revision is
    `>=` the loser's, `merged.revision` is always `>=` every adopted field
    revision — the tombstone invariant (`removed.revision + 1`, unconditional
    tombstone suppression) holds for all production inputs.
  - Merge is symmetric (both argument orders tested), re-merge is a
    `contentEquals` no-op in both directions, decode order is correct, no force
    unwraps / `try!` / `as!` / swallowed errors in the changed code, and the
    wire format stays v4 with purely additive optional keys.
  - **Fixes applied (option [2]: worth-doing-now plus optional):**
    1. Defensive clamp in `ChecklistMerge.mergedItems` —
       `merged.revision = max(coarse, titleRevision, descriptionRevision,
       relativeDateRevision)` — so the coarse clock can never fall below a field
       clock it adopted, even for a hand-crafted/inconsistent payload. No-op for
       production-stamped data.
    2. Updated `legacySeededClocksResolveOneWinningField` expectations for the
       clamp (`revision == 6`).
    3. New regression test `mergedCoarseClockCoversEveryAdoptedFieldClock`
       (skewed field clocks > own `revision`; asserts the high-water mark and
       self-merge idempotence).
    4. Inlined the pass-through `fieldWins` wrapper into `wins`.
- **Remaining manual items**:
  - Manual verification items from `plan.md`/`implement.md` (two-device / watch
    iCloud sync walkthroughs, mixed old+new build) are unchanged and still for
    the user; they cannot be covered by the automated gate.