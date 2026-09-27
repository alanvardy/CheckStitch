# Implementation Summary

Adds an additive, default-`true` `Checklist.showsOnWatch` flag (no
`currentVersion` bump), mutated via `ChecklistStore.setShowsOnWatch` and bound
to a store-backed "Show on watch" toggle in `ChecklistDetailView`. The watch
filters its already-derived collections through new `ChecklistGrouping` helpers
so hidden checklists and all-hidden folders disappear from the watch while iOS
is unchanged. All three phases implemented, each as its own commit.

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | ae07832 | Walking skeleton — toggle on iOS hides a loose checklist on the watch |
| 2     | f14f769 | Folder semantics — folder detail and folder rows honour hiding |
| 3     | 423020c | Hardening — sync conflicts, edge cases, and on-watch verification |

## Automated Checks
- [x] `make test-unit` passes across all phases (503 → 507 → 511 tests in 63 suites)
- [x] `make watch-build` — checkpoint compiles with the delegating `looseChecklists` + `visibleFolders`
- [x] `make build` — iOS target compiles (Phase 2; no accidental app-target use of the new helpers)
- [x] `scripts/l10n-check.sh` prints `l10n-check: ok` (4 catalogs, 156 keys, 6 languages)
- [x] `currentVersion` confirmed unchanged at `5` (`Checklist.swift:477`)
- [ ] `bash scripts/test.sh` full gate — deferred to the review step (checked in `plan.md` remains unchecked by design)

## Manual Verification Items (from the plan)
- [ ] Phase 1: `make run`, open a checklist's detail screen: "Show on watch" appears in its own section, default **on**, with the footer text.
- [ ] Phase 1: Toggle it off, leave and re-enter the screen: it stays off (store-backed).
- [ ] Phase 1: Toggle back on: it flips back.
- [ ] Phase 2: `make run` and open a folder on the phone: its iOS list is unchanged (hidden members stay visible on iOS).
- [ ] Phase 2: (Watch check lands in Phase 3's live pass.)
- [ ] Phase 3: `bash scripts/run-watch.sh` builds, installs and launches `CheckStitchWatch` on the paired Apple Watch.
- [ ] Phase 3: With the watch app open, toggle "Show on watch" **off** for a loose checklist on the phone: the row disappears from the watch's main list.
- [ ] Phase 3: Toggle it back **on**: the row returns.
- [ ] Phase 3: Put two hidden checklists in one folder: the folder row disappears from the watch root, and re-enabling one member brings the folder back.
- [ ] Phase 3: Leave an empty folder: its row stays on the watch root.
- [ ] Phase 3: State what the user should see in the completion artifact (per `AGENTS.md`, sync/hide tickets cannot close on unit tests alone).

## Notes / deviations observed by subagents
- The plan named `CheckStitch/ChecklistStore.swift` and `CheckStitch/ChecklistMerge.swift`, but those files actually live under `CheckStitchCore/Sources/CheckStitchCore/`. Phase 1 adapted the paths; content unchanged.
- The repo enforces memberwise-init argument order (`showsOnWatch` must precede `folderID`), which Phase 2 and Phase 3 test snippets had reversed. Reordered; all tests compile under warnings-as-errors.
- Phase 3's `bash scripts/test.sh` gate checkbox was intentionally left unchecked — the full project-wide gate is owned by the review step, not the phase workers.
- Before phase work, the leftover `DELETEME` placeholder (added by the `chore: start` commit) was removed in a setup commit `51b2cc4` (repo-wide convention) so that the mandated `git rebase origin/main` could run on a clean tree.