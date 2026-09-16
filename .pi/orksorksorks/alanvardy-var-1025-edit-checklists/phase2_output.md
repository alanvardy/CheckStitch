# Phase 2 Output — Reorder checklists

## Commit
- `ac283df` feat: reorder checklists from the main screen edit mode (5 files, +218)
- `8b53c14` docs: check off Phase 2 automated verification in the plan (plan.md, +5/-5)
- Both pushed to `origin/alanvardy-var-1025-edit-checklists` (fast-forward, no force).

## Verification results
- `make test-unit` — **passed**: 237 tests / 33 suites. New `moveChecklists` tests + localization suites for "Move up"/"Move down".
- `make build` — **passed** (simulator, `#if os(iOS)` path).
- `make build-mac` — **passed** (macOS compile leg).
- `make test-ui` — **passed** (UI smoke unchanged, edit mode off at launch).
- `bash scripts/test.sh` — **passed**: printed `gate: ok` (17/17 shell tests, sim build, headless pre-boot, make test, build-mac, watch-build).

## plan.md status
- Phase 2: all 5 automated items `- [x]`; 4 manual items remain `- [ ]` (user confirms).
- Phase 1: all 4 automated items still `- [x]`; 5 manual items remain `- [ ]`.
- 9 checked automated total; no automated item unchecked.

## Changes
1. **Store** (`CheckStitch/ChecklistStore.swift`): added `func moveChecklists(from:to:)` beside `moveItems` — reuses the existing private `moved<T>` helper; silent no-op for out-of-range offsets/destinations; no per-checklist clock stamp (top-level array order is the stored order).
2. **Store tests** (`CheckStitchTests/ChecklistStoreTests.swift`): `// MARK: - moveChecklists` with the 6 plan-mandated tests using the Phase 1 `makeChecklistStore` fixture:
   - `testMoveChecklistsReordersWithinList` — [0]→2 yields `["Hardware", "Groceries", "Travel"]`
   - `testMoveChecklistsToEnd` — 0→3 yields `["Hardware", "Travel", "Groceries"]`
   - `testMoveChecklistsOutOfRangeIsNoOp` — offsets [5], destination 99: order + stored bytes identical
   - `testMoveChecklistsEmptyOffsetsIsNoOp` — `IndexSet()` → onChange counter stays 0
   - `testMoveChecklistsPreservesChecklistIdentity` — id/name/revision/modifiedAt/items/itemOrder byte-equal after reorder (a reorder never wins an LWW round)
   - `testMoveChecklistsPersistsAcrossReload` — reload sees new order
3. **Localization**: `"Move up"` + `"Move down"` keys in `Localizable.xcstrings` (all six languages; translations per plan); both inserted alphabetically in `LocalizationFixtures.swift` ("App" list).
4. **ContentView**: `checklistMoveControls(for:)` (chevron up/down, `.disabled` at first/last row, accessibility labels/identifiers `moveChecklistUp-<uuid>`/`moveChecklistDown-<uuid>`), `moveChecklist(_:up:)` helper (down nudge `to: index + 2`), and the move-control group as the trailing element of the Phase 1 edit-mode row.

## Deviations / observations
- One test bug caught on first `make test-unit` run: `testMoveChecklistsPreservesChecklistIdentity` initially used `to: 2` while asserting end-position order; destination arithmetic (insertion = destination − removed-before count = 1) yields `[Hardware, Groceries, Travel]` for 0→2, so the identity test now moves 0→3. All other tests passed first try.
- Host disk was nearly full (121Mi free on the data volume) during the first test-unit run; xcodebuild logged a cosmetic "log archive creation failed" warning but tests completed. No action needed beyond rerunning (passed). The full gate ran clean.
- `plan.md` was tracked and Phase 1's checkbox updates had already been committed; only Phase 2's updates were uncommitted, hence the small follow-up docs commit.