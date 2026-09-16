# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 6bda11a | Phase 1: Walking skeleton — pick a priority that persists end to end |
| 2     | 42321de | Phase 2: Running a checklist writes the priority to the reminder |
| 3     | dee9e9a | Phase 3: Hardening — back-compat closure and the visible outcome |

Also on the branch (pre-phase, from the mandated rebase + cleanup): `091302a` (rebased branch start), `ce7422b` (chore: remove DELETEME placeholder).

## Automated Checks

- [x] Phase 1: `make test-unit` passes (246 tests / 33 suites — new `ChecklistItemPriority` enum, store mutator, merge axis, codec, and view tests)
- [x] Phase 1: `make build` passes — the `Menu`-in-`Form` compile is the API oracle (iphonesimulator + watchsimulator legs)
- [x] Phase 2: `make test-unit` passes (248 tests / 33 suites — priority carried to the reminder seam, raw-value mapping pinned)
- [x] Phase 2: `make watch-build` passes — the Core protocol change compiles under the watchOS SDK
- [x] Phase 3: `make test-unit` passes (250 tests / 33 suites — export/import/store/item hardening tests)
- [x] Phase 3: `bash scripts/test.sh` prints `gate: ok` (all four platform legs + shell tests + shellcheck)

## Manual Verification Items (from the plan)

- [ ] Phase 1: `make run`; open a checklist → item → confirm a **Priority** section shows `None` with an info icon on the right; tapping it opens a menu listing None/Low/Medium/High with a checkmark on the current value; picking `High` updates the row label
- [ ] Phase 1: Relaunch the app and reopen the item — the value is still `High`
- [ ] Phase 2: `make run`; create an item, set it High, run the checklist; in Reminders.app the created reminder is flagged High (and a `none` item is not flagged)
- [ ] Phase 3: Install the built app on this worktree's pinned simulator and confirm the **Priority** row renders the current value with a working menu — static evidence is not sufficient for this ticket (see the `devicectl`/`simulator` skills). Expected: item screen shows `Priority` section, label on the left, a tappable info control on the right, checkmark on the selected option.

## Notes / Observations

- **Push history**: the mandated start-of-session `rebase origin/main` replanted the branch base (old base `f8694fe` → `091302a` on the newer origin/main tip), so the first Phase 1 push was rejected as non-fast-forward. The remote branch had no unique commits (verified: origin/main tip was an ancestor of HEAD; remote tip unchanged from fetch). The Phase 1 worker escalated; the parent verified the lineage and authorized one `--force-with-lease` push (`6bda11a`), after which Phases 2–3 pushed cleanly fast-forward. No work was lost.
- **Named-argument order quirk**: Swift requires named arguments in declaration order; shorthand enum literals (`.high`) do not infer through `XCTAssertEqual` generics or optionals — assertions use fully-qualified `ChecklistItemPriority.*`.
- **Pre-existing warnings** (unused locals in `ChecklistStoreTests`/`ChecklistImportSessionTests`) are untouched — not from this change.
- **Legacy seam untouched**: `ReminderCreating` / `ChecklistCreator` / `ChecklistViewModel` were intentionally not migrated (per plan Notes) — worth calling out in the PR.
- A stray `DELETEME` placeholder added by the branch's start commit was deleted in the working tree before phase work; its removal was committed as `ce7422b` to unblock the rebase.