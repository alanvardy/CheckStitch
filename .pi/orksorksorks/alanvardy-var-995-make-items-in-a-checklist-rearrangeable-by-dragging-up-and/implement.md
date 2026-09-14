# Implementation Summary

Ticket: `alanvardy-var-995-make-items-in-a-checklist-rearrangeable-by-dragging-up-and` — make items in a checklist rearrangeable by dragging up and down.
Branch: `alanvardy-var-995-make-items-in-a-checklist-rearrangeable-by-dragging-up-and`. Rebased onto `origin/main` (`7aacadf`; the scaffold commit `07f1c87` was rewritten to `44e69e4` by the mandated rebase — the remote held only the old scaffold, so the branch was updated with an approved `--force-with-lease`, carrying PR #31 forward). All four phase commits are pushed.

## Commits

| Phase | Commit    | Description |
|-------|-----------|-------------|
| —     | `f731ce5` | chore: remove ticket scaffold placeholder (DELETEME) |
| 1     | `793f12d` | Phase 1: Model & Codec — `itemOrder` and the v3 migration |
| 2     | `f91202e` | Phase 2: Merge — order reconciliation in ChecklistMerge |
| 3     | `6fd7fdd` | Phase 3: Store — moveItems and the order invariant |
| 4     | `3a5f8d2` | Phase 4: UI — `.onMove` + edit affordance |

## Automated Checks

- [x] Phase 1: `make test-unit` passes (130 tests / 24 suites; codec, item, store suites green)
- [x] Phase 1: `rg -n 'currentVersion = 3'` confirms codec bump (line 226)
- [x] Phase 1: Watch/coordinator/sync suites follow the version bump and stay green
- [x] Phase 2: `make test-unit` passes (137 tests; 7 new merge cases incl. symmetry/idempotence)
- [x] Phase 2: `rg -n 'reconciledOrder|remoteWinsOrder'` confirms the merge wiring
- [x] Phase 3: `make test-unit` passes (10 new store cases, all pre-existing suites green)
- [x] Phase 3: `bash scripts/test.sh` prints `gate: ok` (simulator build, headless pre-boot, test, build-mac, watch-build, shell tests 16/16, shellcheck)
- [x] Phase 3: `rg -n 'func moveItems' CheckStitch/ChecklistStore.swift` confirms the public API
- [x] Phase 4: `make test-unit` passes (incl. new detail-view render smoke)
- [x] Phase 4: `bash scripts/test.sh` prints `gate: ok` (build-mac leg proves the `#if os(iOS)` `EditButton` guard)
- [x] Phase 4: `make test-ui` green (1 UI smoke, 0 failures)

## Manual Verification Items (from the plan)

- [ ] `make run`: create a checklist, add ≥3 items, tap **Edit**, drag a row up and down, confirm the order changes and the item text is unchanged.
- [ ] Relaunch the app (`make run` again): the reordered order persists.
- [ ] On the macOS slice (`make build-mac-signed` + run), confirm the `Form` rows can be reordered by drag without an edit button, and that nothing in the items section regressed (delete still works, text fields still edit).
- [ ] Confirm a reorder does **not** alter any item's text or trigger an item edit (no reminder-affecting behaviour).

## Notes / deviations

- **`self = normalizedOrder()` in `init(from:)`** rejected by the compiler ("Immutable value 'self.id' may only be initialized once"); used the plan's documented fallback (decode into locals, single `self = Checklist(...).normalizedOrder()`).
- **`normalizedOrder()` made `public`** (one-word visibility fix inside the Phase 1 file, landed with Phase 2): Phase 1 had declared it `internal`, but the plan's own Phase 2/3 snippets call it from the `CheckStitch` app module. Without this the plan cannot compile. Should be noted in the PR description.
- **Phase 4 render test adaptation**: the plan's `String(describing: emptyView.body).isEmpty == false` cannot work as written — `.environment(store)` yields a `ModifiedContent` and SwiftUI traps at runtime (`body() should not be called on ModifiedContent`). Adapted to force a real render pass via `ImageRenderer` (cross-platform), which still proves the body evaluates against a real store.
- **Mixed app versions** (accepted by design Q5B): a v2 build classifies a v3 payload `.unsupportedVersion` and refuses to save/sync. Not tested; document in the PR description.
- Pre-existing, out of scope: `testApplyMergesRemoteChecklist` has an unused `let created = store.create()` (`#NoUsage` warning) — leftover from an earlier phase, untouched.