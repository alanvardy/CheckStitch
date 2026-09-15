# Implementation Summary

VAR-1007 — per-item edit screen (description + relative due date).

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 02d0b35 | Localization — strings for the edit screen |
| 2     | dfe15ba | Edit screen and row affordance |

## Automated Checks
- [x] Phase 1: `make test-unit` passes — `LocalizationTests.catalogsHaveAllSixLanguages`, `.nonEnglishValuesDifferFromEnglish`, `.everyRequiredKeyIsPresent` cover the four new keys (201 tests / 30 suites).
- [x] Phase 2: `make test-unit` passes — updated `ItemRow` constructions plus the new `itemRowCarriesItsChecklistForTheEditLink`, `itemEditViewRendersForAnExistingItem`, `itemEditViewRendersNotFoundForAMissingItem` tests (204 tests / 30 suites).
- [x] Phase 2: `make build-mac` passes — both `#if os(iOS)`/`#else` branches of `dueDateField` compile against the macOS SDK.
- [x] Phase 2: `make build` passes — iOS simulator compile.

## Manual Verification Items (from the plan)
- [ ] `python3 -c "import json;json.load(open('CheckStitch/Localizable.xcstrings'))"` exits 0 and the catalog reports all six locales for each new key. (Parsed successfully during Phase 1 verification, but confirming is yours.)
- [ ] `make run`; open a checklist, tap the pencil on a row, type a description, confirm the change is reflected in the detail row after going back.
- [ ] On the edit screen, type `0` → item due today; clear the field → no due date; type `-3` → a past date; confirm the helper caption sits under the date field.
- [ ] Delete the item from another device/sync while the edit screen is open and confirm the not-found placeholder appears (sad path).
- [ ] Confirm the inline description/date fields on the row still type normally (the edit link does not steal the whole row's tap).

## Gate (belongs to review)
- [ ] `bash scripts/test.sh` prints `gate: ok` — run once by the review step.

## Notes / Observations
- Adaptation: `CheckStitch/ItemEditView.swift` imports `CheckStitchCore` in addition to `SwiftUI` (as `ChecklistDetailView.swift` does) — the plan's snippet only imported SwiftUI but the model types live in the Core module; without it the app target does not compile.
- The existing `ItemRow` date placeholder previously fell back to the raw `"Days"` key; Phase 1 localizes it, which is expected per the plan.
- The working tree carries a pre-existing unstaged deletion of the `DELETEME` placeholder file (left by an earlier step in this ticket; the file itself instructs "git rm before merging"). It was deliberately kept out of both phase commits — decide at merge time whether to include the deletion.
- `.pi/orksorksorks/<branch>/medium.md` is untracked and untouched.