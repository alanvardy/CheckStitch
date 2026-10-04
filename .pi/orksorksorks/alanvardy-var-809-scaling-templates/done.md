# Done

- **Branch / head SHA**: `alanvardy-var-809-scaling-templates` @ `9038465`
  (`chore: commit VAR-809 pipeline artifacts, drop DELETEME placeholder`),
  pushed to `origin` with `--force-with-lease` after the pre-session rebase
  (no conflicts to resolve; branch was already linear on `main` @ `b416a18`).
  The `DELETEME` placeholder was `git rm`'d and the `.pi/orksorksorks/<branch>/`
  pipeline artifacts committed.

- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok`.
  Covers `make build` (iOS simulator), the headless simulator pre-boot, `make test`,
  `make build-mac`, `make watch-build`, the shell suite
  (`tests: 26 passed, 0 failed`), and `shellcheck scripts/*.sh scripts/tests/*.sh`.
  Warnings-as-errors is enforced on every compiling leg
  (`warnings_as_errors_reaches_compiling_legs` green). `scripts/l10n-check.sh`
  passed as part of the gate. No failures, no warnings flagged.

- **Review outcome**: one bounded `reviewer` agent (fresh context) over the
  full source diff vs `main` (22 files, +639/−21), plus a parent pass.
  **No blockers (P0/P1) were found.** Verified sound and accepted:
  - `ChecklistScaling.resolve` index math is bounds-safe (no `nil`-unwrap, no OOB,
    closing-paren `))` run guarded, overflow via `multipliedReportingOverflow`)
    and the `((3)))` pass-through fixture holds.
  - `multiple` is a purely additive optional Codable field decoding to `1` with
    no version bump; decode and `setMultiple` both clamp into `multipleRange`.
  - `setMultiple` no-op guard avoids a spurious LWW win; merge/duplicate/import
    carry the field and the coarse revision clock is consistent.
  - `RunChecklistIntent.multiple` is validated before the status pre-check, gate
    reserve, or any create.
  - Localization: all three new keys carry all 6 languages + `LocalizationFixtures`
    entries and the `×%lld` locale-invariant exclusion.

  **Optional improvements noted, not applied** (non-blocking; no fixes were
  clearly worth doing now, so nothing was edited):
  1. `STRING_CATALOG_GENERATE_SYMBOLS = NO` on the app target removes app-wide
     compile-time string-symbol checking to accommodate one ×-leading key
     (verified functionally safe — the app target uses only runtime lookup APIs).
  2. `Bundle.main.localizedString(forKey: "×%lld", value: nil, …)` would render
     the literal `×%lld` if the manual catalog key were ever culled; a hardcoded
     default would be more robust.
  3. `setMultiple` returns `.updated` for a true no-op (semantically loose but
     consistent with the existing `set*` convention and required for sync).
  4. Nits: redundant `second <= text.endIndex`; `reserveCapacity(text.count)` is a
     slight underestimate; the Scaling stepper has no descriptive accessibility value.

- **Remaining manual items**: the device/simulator verification items from
  `implement.md` still require a human run (installed-bundle checks cannot close
  on static evidence per `AGENTS.md`):
  - `make run`: Scaling stepper appears; set `2`, items `Milk ((3))` / `((4)) boxes`
    run as `1: Milk 6` / notes `8 boxes`; stored text stays `Milk ((3))`.
  - Read-only rows preview `×N` + resolved text while `ItemEditView` stays raw;
    badge hidden at Scaling `1`.
  - `bash scripts/run-watch.sh`: Watch detail shows scaled title/description, no badge.
  - Duplicate/export/import preserve the factor.
  - Shortcuts: no Multiple → stored factor; Multiple `4` → that run only; Multiple `0`
    → `Multiple must be between 1 and 99.` with no reminders created.
