# Done

- **Branch / head SHA**: `alanvardy-var-1114-archive-checklists` @ `ed1464a`
  (`review: apply archive review fixes, drop DELETEME, record step artifacts`).
  The completion marker is the follow-up commit containing this file; the
  seven pre-review branch commits (branch-start chore `2ca10a6` + phases
  `5a50cb7`…`07c285a`) were already pushed.
- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok` (simulator build +
  test, macOS compile leg, watchOS build, widget build, shell tests 26/26,
  shellcheck), run **before and after** the review fixes. `make test-unit` →
  `TEST SUCCEEDED` (559 Swift Testing cases in 66 suites + 178 XCTest cases).
  `bash scripts/l10n-check.sh` → `l10n-check: ok` (4 catalogs, 166 keys, 6
  languages). No warnings (warnings-as-errors on).
- **Rebase**: no rebase in progress at session start (`rebase-merge` /
  `rebase-apply` absent); nothing to resolve. Branch was already
  `origin`-aligned (0 behind / 7 ahead of `main`).

## Review outcome

One fresh-context `reviewer` pass over `git diff main...HEAD` (source + tests;
artifacts and `DELETEME` excluded), plus the parent's own scan.
**Verdict: merge OK — zero blockers.**

Applied (user approved `[2]`, fixes worth doing now + optional improvements):

- **`removeArchived(id:)` active-record guard** — `ChecklistStore.swift:646`
  now refuses an active id (`checklists[index].isArchived`), matching
  `archive`/`restore`, so the Archived screen's chokepoint can never
  hard-delete a live checklist. New test
  `testRemoveArchivedRefusesAnActiveChecklist`.
- **Edit-mode reorder with archived rows** (parent finding; reviewer missed
  it) — `ChecklistListViewModel.moveChecklist(id:up:)` computed neighbour
  indices in the full `store.checklists` array while the list renders
  `activeChecklists`. With `[A, X(archived), B]`, "up" on `B` produced
  `[A, B, X]` — visible order unchanged, so the chevron appeared inert. It now
  resolves the neighbour from `activeChecklists` and maps it back to the full
  array. New test `moveChecklistUpSkipsAnArchivedRow`. The drag path
  (`onto:`) was already correct.
- **Single `now()` read in `archive`** — one `stampedAt` stamps both
  `archivedAt` and `modifiedAt`, matching the store's single-read pattern.
- **Trailing newlines** added to `ArchivedChecklistsView.swift`,
  `ChecklistEntity.swift`, `ChecklistWidgetDisplayModelTests.swift`.
- **`DELETEME` placeholder removed** (`git rm`) as the repo convention requires
  before merge.

Optional improvements noted and **declined**:

- Widget empty-state wording when every checklist is archived (shows "No
  checklists" rather than "Edit this widget…"). This follows the plan's
  explicit choice of the existing empty state; no change made.
- Reviewer's conclusion that the reorder index arithmetic was unaffected by the
  archived filter was superseded by the fix above.

**Deliberately not verified by the reviewer**: per-commit scoping of the seven
pre-review commits, device/manual plan steps, and a full language-by-language
catalog read (covered by `l10n-check` + `LocalizationFixtures` instead).

## Remaining manual items

Device-verification steps from `plan.md`, still open (cannot be closed on static
evidence per the repo's sync/render rule):

- **Phase 1** — `make run`; archive a checklist from its detail screen;
  confirm it leaves the main list and stays gone after relaunch; confirm no
  Reminders were created or deleted.
- **Phase 3** — `make run`; archive two checklists; Settings → Archived
  Checklists lists both newest-first; swipe Restore returns one to the main
  list with items intact; archive "X", create active "X", restore → "X 2".
- **Phase 4** — `make run`; archive a checklist, swipe Delete Permanently,
  confirm; gone from the Archived screen after relaunch and a merge; no
  Reminders touched.
