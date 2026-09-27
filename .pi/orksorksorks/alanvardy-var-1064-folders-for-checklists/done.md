# Done

- **Branch / head SHA**: `alanvardy-var-1064-folders-for-checklists` @
  `0548020` (after the review-fix commit; prior tip `f32a795`). Branch was
  rebased cleanly before the session and was 0 commits behind `main`; no
  conflicts to resolve. Pushed with `--force-with-lease`.

- **Mechanical checks**: all green.
  - `bash scripts/test.sh` → **`gate: ok`** — `make build` (simulator) →
    pre-boot own `.simulator_id` → `make test` (150 unit + 1 UI test) →
    `make build-mac` → `make watch-build` → `scripts/tests/run.sh`
    (26 passed, 0 failed) → shellcheck, every Swift leg under
    `WARNINGS_AS_ERRORS`.
  - `bash scripts/l10n-check.sh` → `ok (3 catalogs, 142 keys, 6 languages)`.
  - Post-fix re-validation: `make build` + `make test-unit` (471 tests, all
    passed) then the full gate and l10n again — both green.

- **Review outcome**: two bounded `reviewer` lanes (fresh context, pointed at
  a pre-generated diff): core data/codec/merge/sync/concurrency, and
  UI/watch/localization/tests. Both returned **OK with notes**; **no
  blockers**. My own diff scan cross-referenced their findings.
  - **Fix applied (the one "worth doing now")** — blank folder names were
    reachable from the UI: the `New Folder` alert opens with an empty field,
    so tapping **Done** created a folder named `""` (`uniqueName` returns the
    trimmed empty string). `ChecklistStore.createFolder` now falls back to
    `"New Folder"` for a nil/whitespace-only request, and
    `renameFolder` treats a blank request as a no-op so a folder header can
    never be blanked. Covered by
    `testCreateFolderWithBlankNameFallsBackToDefault` and
    `testRenameFolderToBlankNameKeepsTheExistingName`.
  - **Optional improvements applied** (requested via menu `[2]`):
    - the unknown-`folderID`→loose rule is now a single
      `ChecklistGrouping.isLoose(_:knownFolderIDs:)` used by both
      `ChecklistGrouping.sections` and `ChecklistListViewModel.checklists(in:)`
      (drift-proof);
    - `ContentView` hoists `listVM.checklists(in:)` to a local in both the
      loose group and each `folderSection`, removing the per-row O(n²)
      recomputation in `body`;
    - documented the sticky folder-tombstone semantics in `ChecklistMerge`;
    - added the missing trailing newline to `ChecklistGroupingTests.swift`.
  - **Declined / deferred (with reason)**:
    - *Empty "Loose" heading when every checklist is filed* — matches the
      approved plan verbatim (plan lines 296–298 and the watch
      `sections.count > 1` gate); deferred rather than deviate from the plan.
    - *`moveFolder(id:up:)` can compute `to: -1`* — already neutralised:
      `ChecklistStore.moved` range-guards the destination and returns `nil`
      (no-op), and the boundary chevrons are disabled.
    - *Sticky folder tombstone beats a concurrent higher-revision rename* —
      intentional product decision (a delete is permanent; recreation mints a
      new UUID) matching the grow-only checklist-tombstone invariant, pinned
      by `folderTombstoneBeatsALowerRevisionLiveFolder`. Now documented.
    - *Double context push on folder delete* (`onChange` of both
      `store.checklists` and `store.folders` fire) — harmless latest-wins
      duplicate; delaying coalescing would add complexity and risk for no
      observable benefit.

- **Remaining manual items**: the plan's manual verification list still
  requires a human + real hardware (sync/UI tickets cannot close on static
  evidence):
  - `make run`: create a folder in edit mode, move a checklist in/out,
    rename, reorder, delete — confirm persistence across relaunch; an empty
    folder and an all-loose list render cleanly.
  - Two-device sync: a folder created + a membership moved on one side
    converges (no duplicate); a folder deleted on one side stays gone after
    the other side re-syncs (no resurrection).
  - `bash scripts/run-watch.sh`: the watch shows the same folder names as
    sections with the loose group last; renaming/reordering on the phone
    updates the watch after the next context push.
  - `bash scripts/run-devices.sh` (real-device close-out): the installed app
    shows folder sections on iPhone + host Mac and syncs to the paired watch.
  - `make build-mac-signed` (provisioning-bearing leg, outside the gate) was
    not run in this step.