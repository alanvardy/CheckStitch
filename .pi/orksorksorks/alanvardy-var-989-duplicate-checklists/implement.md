# Implementation Summary

Duplicate Checklist feature landed in three dependency-ordered commits: store
behaviour → view surface → localization. No schema/envelope change (stays
version 2), no tombstones, no EventKit, no entitlement, no `project.pbxproj`
edit.

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | a0e9471 | Store — duplicate with fresh identifiers and names |
| 2     | 768c031 | View — the button and its name alert |
| 3     | 1305acc | Localization — catalog and fixtures |
| —     | a0f0d25 | chore: remove ticket scaffold placeholder (pre-existing `DELETEME` deletion, landed to unblock the required rebase) |

## Automated Checks
- [x] `make test-unit` passes, including all new `ChecklistStoreTests` cases (128 tests / 24 suites)
- [x] `make test-unit` passes, including the new `ChecklistDetailViewTests` case
- [x] `make build` passes (the view is shared by iOS and macOS)
- [x] `make test-unit` passes, including `LocalizationTests` presence and non-English-differs checks for the three new keys
- [x] `make build` passes
- [x] `bash scripts/test.sh` prints `gate: ok` (iOS sim build → simulator pre-boot → `make test` → `make build-mac` → `make watch-build` → shell tests → `shellcheck`)

## Manual Verification Items (from the plan)
- [ ] Read the diff: `checklists` envelope version is still 2, no tombstone path added, `uniqueName` and `save()` untouched
- [ ] `make run` on the simulator, open a checklist with items: the trailing section reads Add Item / **Duplicate Checklist** / Remove Checklist, with Remove still last and still destructive-styled
- [ ] Tap Duplicate Checklist: an alert titled "Duplicate Checklist" appears with the name field prefilled `"<original name> copy"`, Cancel and Duplicate buttons
- [ ] Confirm with the prefill: the list screen shows a new `"… copy"` entry holding the same item titles; the original is unchanged
- [ ] Duplicate the same checklist again and accept the prefill: the new entry is `"<original> copy 2"` (the prefill is re-disambiguated on commit)
- [ ] Cancel: no new checklist is created
- [ ] `make build-mac-signed` then launch the macOS app and repeat one duplicate to confirm the shared view renders the button and alert there
- [ ] Open the alert on a device/simulator set to a non-English language and confirm the title, message and Duplicate button are translated
- [ ] Re-read the catalog: keys are alphabetical, `extractionState` is `"manual"`, and no other block was touched
- [ ] `git log` shows one commit per phase; the tree is clean

## Observations
- Per the plan's resolved decisions: the `" copy"` suffix is a plain literal
  (no format key — `uniqueName` is shared with `create`/`rename`); a taken
  name is silently disambiguated, never alerted; the copy is appended at the
  end and the screen does not navigate to it; a blank name falls back to the
  default.
- `ChecklistStore` lives in the app target, so both test suites keep
  `@testable import CheckStitch` (no switch to Core-only import was needed).
- `medium.md` (design-step artifact) was folded into the tracking commit for
  the artifact directory, per the repo convention that step artifacts under
  `.pi/orksorksorks/<branch>/` are committed.
- No deviations from the plan were needed in any phase.