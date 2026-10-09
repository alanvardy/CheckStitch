# Done

- **Branch / head SHA**: `alanvardy-var-1120-export-folders`
  @ `b8137f7` (`review: apply VAR-1120 review fixes`). The completion marker is
  the follow-up commit containing this file; the pre-review commits (branch-start
  chore `20b6c95`, phases `d618e7f`/`cf3e22f`/`323a1c6`, artifact chore
  `583415a`) were already pushed.
- **Mechanical checks**: `bash scripts/test.sh` → **`gate: ok`**, run **before
  and after** the review fixes — simulator build (`make build`) → headless
  pre-boot → `make test` (212 XCTest + 1 UI test + Swift Testing suite) →
  `make build-mac` → `make watch-build` → `scripts/tests/run.sh` (26/26) →
  `shellcheck`. Warnings-as-errors on; both runs green. The new test
  `unselectedCandidatesFolderIsNotMinted()` ran and passed in the post-fix gate.
- **Rebase**: none in progress at session start (`rebase-merge` /
  `rebase-apply` absent); no conflicts. Branch was `origin`-aligned; pushed with
  `--force-with-lease` (fast-forward, no history rewritten).

## Review outcome

One fresh-context `reviewer` pass over `git diff main...HEAD` (source + tests;
`.pi/orksorksorks` artifacts excluded), plus the parent's own scan of the store,
session and merge sources. **Verdict: merge OK — zero blockers.**

The reviewer confirmed the load-bearing claims with evidence: export filters to
referenced folders (deduped, empty tombstones/`deviceID`), the folder-aware
store write keeps `resolveOrCreateFolder`'s no-`save()` safe (the minting
candidate is always inserted and saved in the same commit), Keep Existing mints
nothing, orphans land loose, same-name collisions collapse, and the new tests
are non-vacuous.

Applied (user approved `[1]` — fixes worth doing now):

- **Vanished-target folder leak** (`ChecklistImportSession.swift`, `decide(.replace)`):
  `localFolderID(...)` was evaluated as an argument *before* `store.importReplace`,
  so a conflict target deleted by sync mid-dialog left a folder appended but
  unsaved (later persisted as an empty folder by the next unrelated save). Now
  guarded by `store.checklist(id: conflict.id) != nil` before resolving/minting.
- **Unticked-candidate coverage** (`ChecklistImportSessionTests.swift`,
  `unselectedCandidatesFolderIsNotMinted`): pins deviation #3 — a two-folder /
  two-candidate payload committed with one candidate selected mints only the
  selected candidate's folder and imports only that checklist.

Declined / deferred (with reasons):

- **Name-based folder matching creates a fresh local id** for an imported
  folder, so under LWW a same-name folder can coexist across devices. Already
  documented by `renamedLocalFolderGetsANewFolderOnImport`; accepted design
  limitation, not a bug.
- **A checklist whose `folderID` names a deleted/tombstoned folder** exports it
  loose silently. Consistent with the intended "orphan lands loose" design.
- **`discard()` does not clear `fileFolders`** — harmless (candidates are reset,
  so it is unreadable); pure nit, not changed.

**Not verified by the reviewer**: device/simulator manual steps below, and any
behaviour outside the diff's direct context.

## Remaining manual items

Simulator/device verification from `plan.md` (sync/render tickets cannot close on
static evidence):

- **Phase 1** — `make run`: create a folder "Groceries", move a checklist into
  it, select that checklist, Export → open the JSON and confirm `"folders"`
  contains "Groceries" and `"folderTombstones"` is `[]`.
- **Phase 3 (optional)** — on a fresh simulator install, import a folder-bearing
  export → the imported checklist appears under a folder of the same name; import
  the same file again → still one folder.
