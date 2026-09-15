# Implementation Summary

JSON export + import for CheckStitch, implemented in four phases (each green via
`make test-unit` before the next) plus a final-gate test fix. An export is a
valid `ChecklistCodec` payload (`.loaded`) so the round trip is lossless; every
imported mutation flows through `ChecklistStore` (replace records a tombstone
and pushes via the existing `save → onChange → schedulePush` chain).

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `43b987e` | Export payload + document (pure serialization) |
| 2     | `bb96869` | Store import primitives (data access) |
| 3     | `79add1a` | Import session (business logic) |
| 4     | `5cdcef0` | SwiftUI surface + localization (presentational) |
| fix   | `31588d5` | fix: assert export wrapper bytes semantically — see below |

## Automated Checks

- [x] `make test-unit` green after every phase (all 30+ suites incl. `ChecklistExportTests`, new store import tests, `ChecklistImportSessionTests`, `ExportChecklistsViewTests`, all `LocalizationTests`)
- [x] `make build` (simulator) green
- [x] `make test` (unit + UI smoke) green
- [x] `make build-mac` green
- [x] `make watch-build` green
- [x] `bash scripts/tests/run.sh` — 17 shell tests pass
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean
- [x] `bash scripts/test.sh` → `gate: ok`
- [x] No `project.pbxproj` edit needed (synchronized groups picked up the new files)
- [x] All automated plan.md boxes checked (phases 1–4 + Final gate, except the manual `build-mac-signed` panel check)

## Fix (commit `31588d5`) — why the gate initially failed

The gate failed on Phase 1's `testFileWrapperCarriesEncodedBytes` — not a stale
object (the earlier subagent attribution was wrong) but an invalid assertion:

- The test compared **two independent `JSONEncoder` encodes byte-for-byte**
  (`doc.data` vs `ChecklistExport.data(selected)`). Both encodes were semantically
  identical, but `JSONEncoder` key **order is not stable across encodes** (the two
  1004-byte payloads differed only in key ordering), so the assertion flaked
  (passes 2 runs, fails the 3rd, reproducible even from a clean DerivedData).
- Fix: decode the document's bytes and compare the **envelope** (`env.checklists
  == selected`, `deviceID == ""`, `tombstones.isEmpty`) — deterministic, and still
  proves "the export bytes classify `.loaded` and carry the selected set".
- Production code was correct throughout; this was test-mechanics only.

## Manual Verification Items (from the plan)

These are the user-confirmed items; I did not attempt them.

- [ ] `make build-mac-signed` succeeds with no entitlement change; launch the app, Export → multi-select 2 of 3 → save → the file is named `CheckStitch-<date>.json` and its bytes classify `.loaded` (drop it into a scratch `ChecklistCodec` check or just re-import it).
- [ ] macOS: Import the exported file on a store that already owns a same-named checklist → the conflict dialog appears per conflict, each choice behaves (Replace swaps + records a tombstone; Keep Both yields `"<name> 2"`; Keep Existing leaves the local copy).
- [ ] macOS: delete/rename a checklist, then confirm the store pushes (iCloud sync status stays quiet); an import with no conflicts inserts immediately.
- [ ] Import a corrupt file (`echo hi > /tmp/bad.json`) and a future-version file → "This file isn't a CheckStitch export." / "…newer version…" alert; nothing changes in the list.
- [ ] Device/simulator run (`bash scripts/run-devices.sh`): the file panel opens, the security-scoped read succeeds, and the same export→import loop works.
- [ ] iOS: the floating `…` plate renders beside Settings, is hidden on a pushed screen, and the accessibility audit in the UI smoke stays green.
- [ ] Final gate: `make build-mac-signed` manual panel check complete.

## Notes / observations

- `FileDocument` is deprecated on this toolchain in favour of `Document`, but
  remains supported and the plan explicitly chose it (`fileExporter` binds
  `FileDocument`). Non-blocking note for review.
- `fileWrapper` returns exactly `data`; the framework supplies its own
  `WriteConfiguration` (no accessible initializer), so the wrapper-path test
  asserts on the decoded envelope of that data rather than invoking `fileWrapper`
  with a hand-built config.
- `AppGroup.entitlements` was left unchanged pending the `make build-mac-signed`
  panel check (the plan's conditional item 5).
