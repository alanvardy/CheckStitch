# Done

- **Branch / head SHA**: `alanvardy-var-1025-edit-checklists` @ `45ad04d`
  (`fix: animate edit-mode move/remove and harden the remove dialog (review)`).
  Rebased onto `origin/main` with no conflicts (merge-base == `origin/main`);
  pushed fast-forward.

- **Mechanical checks**: `bash scripts/test.sh` → **`gate: ok`** (EXIT=0):
  simulator `make build` → headless pre-boot → `make test` → `make build-mac` →
  `make watch-build` → 17/17 shell tests → `shellcheck scripts/*.sh`. No
  warnings flagged.
  - First gate attempt failed with `No space left on device`; cleared
    regenerable Xcode `DerivedData` for this and other worktrees (no user data),
    freeing 5.1 GiB, then passed. Re-ran the gate after the review fixes; green.

- **Review outcome**: `reviewer` (fresh context) reported **no blockers**.
  Correctness cross-checked by the parent: the ternary `Button` label does
  localize (compiler dump shows `ternary_expr type="LocalizedStringKey"`);
  `moveChecklists` needs no revision bump (`ChecklistMerge` keeps local order);
  `removeChecklists` tombstone invariant matches `delete(id:)`; `moved<T>` no-ops
  on the first-row-up / last-row-down edges.
  - **Fixes applied** (user chose option [2]):
    1. `ContentView.swift` — `removeChecklist` / `moveChecklist` now mutate
       inside `withAnimation`, so row removal and reorder actually animate
       (the plan's manual item promised this).
    2. `ContentView.swift` — the destructive Remove button clears
       `checklistPendingRemoval` explicitly instead of relying on dialog
       dismissal to fire the `isPresented` setter.
    3. `plan.md` — corrected the "reorder is carried to other devices" prose:
       order is pushed but stays per-device (local-wins), not globally
       convergent.
  - **Not applied** (declined as speculative, no on-device evidence): hoisting
    the second `.confirmationDialog` off the root modifier chain; the P2
    newer-version-payload observation (consistent with all existing mutations).
  - **Deferred to the merge step**: `git rm DELETEME` — the branch-start
    placeholder is intentionally left for the merge/teardown alias, which
    performs the removal; removing it here could break that alias.

- **Remaining manual items**: the 9 plan.md manual verification items are
  unchecked and need a human on device/simulator — Edit shows red minus +
  chevrons and hides play/navigation; Remove dialog Cancel/Remove behaviour and
  order preservation; last-removal lands on empty state; existing Reminders
  untouched; macOS title-bar Edit item; chevrons disabled at row ends; reorder
  animates and survives relaunch; non-editing state visually unchanged.
  Plus the merge-time `git rm DELETEME`.