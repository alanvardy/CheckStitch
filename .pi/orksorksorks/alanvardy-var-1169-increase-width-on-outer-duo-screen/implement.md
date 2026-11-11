# Implementation Summary

## Commits

| Phase | Commit    | Description |
|-------|-----------|-------------|
| 1     | `91be011` | Walking skeleton — Duo-outer card widens end to end |
| 2     | `03ceb94` | Header row and empty state use the shared width |
| 3     | `a55c8dc` | Harden Duo layout scoping with boundary and matrix tests |

All three commits are pushed to `alanvardy-var-1169-increase-width-on-outer-duo-screen`.
Each commit is scoped to its own phase's source/test files — no phase committed
`plan.md` or anything under `.pi/orksorksorks/`.

## Automated Checks

- [x] Phase 1 — `make test-unit` green (700 tests / 73 suites; new `ChecklistLayoutTests` and `DuoDisplayTests`, untouched `ChecklistWidthTests`)
- [x] Phase 1 — `make build` green (iOS simulator leg, `uname`/`Darwin` `#if os(iOS)` branch)
- [x] Phase 1 — `make build-mac` green (macOS leg, `#else return ""` branch; warnings-as-errors)
- [x] Phase 2 — `make test-unit` green (700 tests / 73 suites)
- [x] Phase 2 — `bash scripts/tests/run.sh` green (45 passed, 0 failed), including the new `contentViewHasNoLiteralContentGutter` case
- [x] Phase 2 — `make build` green
- [x] Phase 3 — `make test-unit` green (704 tests / 73 suites; expanded boundary sweep + Duo matrix)
- [x] Phase 3 — `./scripts/test.sh` printed `gate: ok` (build → sim pre-boot → test → build-mac → watch-build → `scripts/tests/run.sh` → shellcheck)

## Notes / Deviations

- `OrientationPolicy.swift` (referenced in the plan's Phase 1 preamble) does not exist in this repo;
  `ChecklistLayout` was written to mirror `ChecklistWidth`'s shape instead. No functional impact.
- The plan's compiler fallback note (`nonisolated public static var` for the gutter constants) was
  not needed — `nonisolated public static let` compiled cleanly.
- Phase 2 also updated one adjacent comment that referenced "32pt margins" so no literal `32`
  remained in `ContentView.swift`, matching the plan's stated goal. Functionally inert.
- Phase 3 used the plan's documented ULP fallback directly for the 382 pt safe-area case
  (`abs(actual - 305.6) < 0.0001`).
- Pre-existing, unrelated working-tree state left untouched: an unstaged deletion of the tracked
  file `DELETEME`. It belongs to no phase and was not restored or staged by any subagent.

## Manual Verification Items (from the plan)

- [ ] Phase 1: On a real iPhone Duo outer display in portrait, the checklist card is visibly wider
      than before (cap uses the 0.8 fraction; gutter is 16).
- [ ] Phase 1: On every other device/simulator/orientation the card width and gutter are unchanged.
      (Not runnable in the gate: the simulator reports the host arch; accepted risk, to be stated in the PR.)
- [ ] Phase 2: On a real Duo outer display in portrait, the edit-toggle header row and the empty-state
      card share the widened card's column edges (16 pt gutter).
- [ ] Phase 2: On other devices the header row still aligns with the card.
- [ ] Phase 3: PR body states the accepted risk — the Duo device path is unit-tested only (the
      simulator reports the host arch) — and describes what a user should see on a real Duo outer
      screen in portrait (a visibly wider card and a 16 pt gutter).
