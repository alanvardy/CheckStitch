# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | f5a7fea | walking skeleton — an OS share / Open-In reaches the store |
| 2     | fbb7487 | selection — only ticked checklists import |
| 3     | c31ad9e | robustness — bad and repeated arrivals never touch the store |
| 4     | (artifacts commit) | hardening, presentation, on-device verification wiring |
| fix   | f4f6dc3 | storeIsByteIdenticalAfterCancel uses value equality (codec bytes not stable) |

## Automated Checks
- [x] `make test-unit` passes — shared-inbox suite + session/VM stage/commit/decide suites + export suite (377 tests, 49 suites)
- [x] `make build` passes (simulator; warnings-as-errors) — Info.plist merge + both delegate signatures + `ChecklistSelectionView` type-check
- [x] `make build-mac-signed` succeeds (real macOS app, App Group entitlements embedded)
- [x] `make test-ui` passes (single `CheckStitchUITests` launch/accessibility smoke)
- [x] `bash scripts/tests/run.sh` green — `tests: 25 passed, 0 failed`, incl. `documentTypeRegistrationWiresInfoPlist`
- [x] `bash scripts/test.sh` prints `gate: ok`

## Deviations from the plan (all verified against the gate)
- **Phase 1 (pbxproj):** because `PBXFileSystemSynchronizedRootGroup` auto-includes
  `CheckStitch/Info.plist` in Copy Bundle Resources (duplicating the processed
  plist and failing the build), a `PBXFileSystemSynchronizedBuildFileExceptionSet`
  (`membershipExceptions=Info.plist`, target `…0100000000`) was added and
  referenced from the root group — the Xcode-native way to pair a custom plist
  with a synchronized group. This keeps the plan's **primary** merge path (no
  `INFOPLIST_KEY_…` fallback needed).
- **Phase 3 (`storeIsByteIdenticalAfterCancel`):** the plan asserted byte equality
  of two `ChecklistCodec.encode` calls over the (unchanged) store. The codec's
  JSON encode is **not byte-stable** across two encodes of equal input (verified:
  two back-to-back encodes of an untouched store differ), so the assertion could
  never pass. The test now asserts the plan's intent — cancel leaves
  `checklists`/`tombstones` value-identical — instead of encoded bytes.
- The `gate: ok` result above was verified **independently** by the implementing
  agent's parent after the codec byte-equality fix; the earlier "gate: ok"
  reported by the implementation worker was not reproducible until that fix.

## Manual Verification Items (from the plan)
- [ ] `make run`; the app launches normally (plist regression check)
- [ ] Put a CheckStitch JSON in Files → tap → "Open In / Share → CheckStitch" → the app foregrounds and the file's checklists appear in the list (all of them)
- [ ] Open the same file twice in a row from Files — the second open does not double-import (idempotent inbox)
- [ ] `make run` → in-app "Import" from Settings shows the checkmark sheet with all rows ticked; untick one, Import → only the ticked checklist appears
- [ ] Repeat and press Cancel (and separately swipe the sheet down) → the list is unchanged
- [ ] Import a file whose only checklist name already exists, untick it, Import → **no** conflict dialog and the list is unchanged
- [ ] Import with a conflicting name ticked → the existing Replace / Keep Both / Keep Existing dialog appears once per ticked conflict
- [ ] Share a plain (non-CheckStitch) `.json` from Files → "Couldn't import" alert, no selection sheet
- [ ] Share two different CheckStitch files back-to-back → the second file's checklists are the ones offered
- [ ] Cold-start share (app killed) → exactly one selection sheet with the file's checklists
- [ ] `bash scripts/run-devices.sh` installs + launches on the real iPhone (and the host Mac)
- [ ] On the iPhone: open Mail with a `CheckStitch-yyyy-MM-dd.json` attachment → Share → **CheckStitch** is offered → tapping it foregrounds CheckStitch and lands on the **selection screen** listing the file's checklists
- [ ] Untick one checklist → Import → only the ticked checklists appear in the CheckStitch list
- [ ] Share the same file again from Mail → the selection screen appears again (the app is already running)
- [ ] Share a non-CheckStitch `.json` from Files → "Couldn't import", no sheet
- [ ] On the host Mac: Open With → CheckStitch from Finder opens the selection sheet (macOS leg of the document type)

## Provider-UTI mitigation (design open risk 2)
If on-device the Share Sheet does not offer CheckStitch, widen `LSItemContentTypes` to
`["public.json", "public.data"]` in `CheckStitch/Info.plist` and rebuild. Widen only
if the device check proves it necessary.