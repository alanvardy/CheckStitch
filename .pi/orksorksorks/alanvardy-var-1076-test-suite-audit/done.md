# Done

- **Branch / head SHA**: `alanvardy-var-1076-test-suite-audit` @ `147cc0c`
  (pushed). Review-step commits: `de84312` (workflow artifacts), `147cc0c`
  (`done.md`), plus the optional-fixes commit that carries this note.
- **Rebase**: no rebase in progress at session start (`rebase-merge` /
  `rebase-apply` dirs did not exist); nothing to resolve.
- **Mechanical checks**: `bash ./scripts/test.sh` → **`gate: ok`** run twice
  (once pre-fixes, once after the optional fixes): simulator build +
  `make test`, macOS compile leg, watchOS build, `scripts/tests/run.sh`
  26/26, shellcheck. `make test-unit` → **449 tests / 60 suites passed**.
  Warnings-as-errors flag is enforced on every compiling leg. No blockers.

## Review outcome

One fresh-context `reviewer` pass over `git diff main...HEAD` (source + tests
+ artifacts). **Verdict: merge OK — zero blockers.**

- **Blockers**: none.
- **Fixes worth doing now**: none substantive. Every production refactor was
  confirmed behaviour-preserving and every new test confirmed meaningful:
  - `SettingsDataActionRoute` is a 1:1 parallel of `SettingsDataAction`;
    `ContentView.perform` switching over it is exhaustive-by-construction.
  - `ChecklistSyncDiagnostics.record` / `shouldResetFile` are pure
    extractions; rotation comparison is unchanged and boundary tests are
    correct (exactly the limit true, limit−1 false).
  - `moveChecklistFirstUp/LastDown` exercise the real
    `ChecklistStore.moved` boundary (`nil` out of range).
  - Good sad-path coverage: `readReturnsNilWhenEmpty`, double-`cancel`
    idempotence, take-twice→`nil`.
- **Optional improvements — applied on request (item [2])**:
  - Trailing newlines added to the seven new suites
    (`AppEnvironmentTests`, `AppGroupTests`,
    `ChecklistExportDocumentTests`, `ChecklistSyncDiagnosticsTests`,
    `ChecklistSyncingContractTests`, `ColorCrossPlatformTests`,
    `ContentViewSettingsActionTests`).
  - `diskSizeLimit` de-duplicated: now `internal static` on
    `ChecklistSyncDiagnostics` and referenced by both rotation-boundary
    tests instead of the hardcoded `64 * 1024`; the doc comment records why
    it is internal.
  - `ColorCrossPlatformTests` gained a comment stating it is a mapping
    contract pin only (both sides resolve `windowBackgroundColor`, so it
    cannot detect a wrong system colour).
  - `AppGroupTests` `.standard`-probe concern deliberately **not** changed:
    the probes are UUID-keyed and `defer`-removed, and the fallback branch
    is genuinely unforceable (`findings.md` #2) — the reviewer itself rated
    it acceptable.
- **Reviewer suggestion rejected**: the claimed "unused `import
  CheckStitchCore`" in `ContentViewSettingsActionTests.swift:2` is
  **load-bearing** — `Checklist` is declared in
  `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:145`, and the
  `\.id` key paths resolve through it. Left in place.
- **Behaviour note (intentional, from the plan)**: a fieldless
  `ChecklistSyncDiagnostics.record` now emits `"[watchSend]"` rather than
  the old `"[watchSend] "` with a trailing space. Syslog greps are
  contains-style, so no consumer keys on that trailing space. Documented in
  `findings.md`/plan as deliberate.

## Remaining manual items

From `plan.md` / `implement.md` (device-only, cannot be verified headlessly):
- Phase 1: on-device records unchanged — after a run, `devicectl`/Console
  still shows `[<gate>] k=v` lines.
- Phase 2: `make run`, Settings → Export presents the multi-select;
  Settings → Import presents the file importer (behaviour-preserving
  refactor); reordering with move arrows still moves first/last unchanged.
- Phase 3: `make run`, app launches, list background renders as before; no
  crash from the App Group UserDefaults.
- Phase 4: `make run`, export a checklist to Files → a `.json` document that
  re-imports.
- Phase 6: `findings.md` reviewed — every entry has severity + evidence and
  none describes a silently applied fix.