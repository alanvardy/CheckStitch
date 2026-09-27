# Done

- **Branch / head SHA**: `alanvardy-var-1102-drag-to-move` @ `2c3f41c`
  (`fix: clear stale drag state on cancel and reject foreign drops`)
- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok` both before and
  after the review fixes. `make test-unit` 485 → 487 tests passing (2 added).
  Covers `make build` (iOS sim, warnings-as-errors), `make test`,
  `make build-mac`, `make watch-build`, `scripts/tests/run.sh` (26 passed),
  `shellcheck`. No warnings flagged; no blockers from mechanical checks.
- **Rebase**: no conflicts — no rebase was in progress and the branch was
  already based on `main`.
- **Review outcome**:
  - One bounded `reviewer` pass over the 3-file source diff (the `DELETEME`
    placeholder removal and step-artifacts commits are chores). Fresh context.
  - **Blocker fixed (#1)**: a cancelled drag never reached `performDrop`, so
    `draggingChecklistID`/`draggingFolderID` leaked and could drive a move when
    a later drag of the other kind passed over rows (silent persisted-order
    corruption). Fix: each `onDrag` clears the other kind's id, edit-mode exit
    clears both, and `performDrop` rejects a drop unless a drag of its own kind
    is in flight. `ContentView.swift`.
  - **Fix applied (#2)**: symmetric unknown-id no-op tests for
    `moveChecklist(id:onto:)` (`dragChecklistOntoUnknownIDIsANoOp`,
    `dragUnknownChecklistIsANoOp`).
  - **Fix applied (#3)**: doc note that `moveChecklist(id:onto:)` is called once
    per row entered during a live-reorder drag.
  - **Optional (declined, remains manual)**: on-device check that a long scrub
    over rows settles without oscillation — already an explicit manual item in
    `implement.md`; static review cannot confirm SwiftUI runtime behavior.
  - **Deferred**: duplicate `import CheckStitchCore` at `ContentView.swift:1,3`
    is pre-existing on `main`, out of this diff's scope.
- **Remaining manual items**: the device/visual checks listed in
  `implement.md` (Phase 1 checklist drag within/loose, cross-section no-op,
  boundary drag, edit-mode tap behavior; Phase 2 folder drag, collapsed-folder
  drag, row↔header no-op, chevron/Move-to-Folder still work). Sync/render
  tickets cannot close on static evidence — verify the installed bundle on the
  target.