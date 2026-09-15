# Done

- **Branch / head SHA**: `alanvardy-var-997-import-and-export-checklists-as-json` / `61edeac`
  (rebase onto `main` was already reconciled: 0 behind, tree clean; pushed with
  `--force-with-lease`).
- **Mechanical checks**: `./scripts/test.sh` → **`gate: ok`** (exit 0), run before
  and after the review fixes. Covers `make build` (simulator), 212 unit tests in
  32 suites, `make build-mac`, `make watch-build`, 17 shell tests, and
  `shellcheck`. No lint/build blockers; only expected `linkd`/URLError noise in
  the test logs.
- **Review outcome**: one fresh-context `reviewer` over the full code diff plus my
  own scan — **no blockers**.
  - **Fixed now**:
    - `CheckStitch/ContentView.swift` — a file read failure (I/O, permissions) no
      longer reports "This file isn't a CheckStitch export."; the read is split
      from the decode and both paths return explicitly.
    - `CheckStitch/ChecklistImportSession.swift` — `prepare` now resets
      `pending`/`summary` at entry, matching its doc comment even across a
      throwing call; the (dead-work) v1/v2 migration branch is documented as
      normalisation-only.
    - `CheckStitchTests/ChecklistExportTests.swift` — new test exercises
      `filename()`'s default `.now`/`.current` path by shape, not a fixed date.
  - **Optional improvements declined**: localising the hardcoded
    `ChecklistImportError.message` strings (deliberate, documented decision to
    mirror `ReminderRunOutcome.errorMessage` and keep them out of the catalog);
    a test for the conflict-dialog dismissal setter (would require widening
    private `ContentView` view internals for little value, and the underlying
    `decide(.keepExisting)` is already covered).
  - **Ignored/deferred**: store ordering of conflict-resolved items (cosmetic);
    main-actor encode/decode jank (matches the app's single-threaded norm).
- **Remaining manual items** (from `plan.md`, not automatable here):
  - `make build-mac-signed` succeeds with no entitlement change; launch and run
    the Export → save → re-import loop, file named `CheckStitch-<date>.json`.
  - macOS conflict dialog per conflict (Replace tombstones + swaps; Keep Both →
    `"<name> 2"`; Keep Existing leaves local).
  - Corrupt + future-version files produce the right alerts and no list change.
  - Device/simulator run via `bash scripts/run-devices.sh` for the file panel and
    security-scoped read.
  - Reviewer's device-only unknowns: (a) first conflict is presented
    synchronously while later ones defer through `DispatchQueue.main.async` —
    confirm none are dropped/double-handled; (b) user-CANCEL behaviour of
    `fileImporter`/`fileExporter` on macOS/iOS (risk of a spurious alert).
  - Product decision to confirm: free-name checklists are committed (and pushed)
    before any conflict is answered; there is no whole-import abort.
  - iOS: floating `…` plate renders beside Settings, hidden on pushed screens,
    UI-smoke accessibility audit stays green.