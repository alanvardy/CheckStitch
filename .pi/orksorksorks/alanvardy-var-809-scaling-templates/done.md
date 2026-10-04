# Done

- **Branch / head SHA**: `alanvardy-var-809-scaling-templates`; branch head is the
  `refactor: apply review optional improvements for VAR-809` commit, whose parent
  `9038465` is the reviewed code head. Pushed to `origin` with `--force-with-lease`.
  The branch was already linear on `main` @ `b416a18` (no rebase conflicts); the
  `DELETEME` placeholder was `git rm`'d and the `.pi/orksorksorks/<branch>/`
  artifacts committed.

- **Mechanical checks**: `bash scripts/test.sh` → `gate: ok` (re-run after the
  optional fixes). `make test-unit` is 556 tests / 66 suites green;
  `scripts/l10n-check.sh` reports `ok (4 catalogs, 162 keys, 6 languages)`.
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

  **Optional improvements applied (user chose [2])**:
  1. Badge lookup now passes a hardcoded `"×%lld"` fallback to
     `Bundle.main.localizedString(forKey:value:table:)`, so a missing catalog key
     renders the intended `×N` rather than the literal key
     (`ChecklistDetailView.swift`).
  2. Removed the redundant `second <= text.endIndex` guard in
     `ChecklistScaling.resolve` (`ChecklistCreator.swift`).
  3. Added an accessibility hint to the Scaling stepper describing what it does,
     as a new all-6-language localized key
     `"Scale item markers by this factor when creating reminders."` in the App
     catalog plus its `LocalizationFixtures` registration.

  **Optional improvements deliberately not applied**:
  1. `STRING_CATALOG_GENERATE_SYMBOLS = NO` remains: the `×`-leading format key
     cannot be replaced by a symbol-generatable key without rendering `N×`
     instead of `×N`, so the scoped flag is the accepted trade-off (Option A).
  2. `setMultiple` keeps returning `.updated` for a true no-op — changing it
     would break the existing `set*` return convention and its sync test.
  3. `reserveCapacity(text.count)` left as-is: it is only a capacity hint and no
     principled larger bound exists without extra work in the hot path.

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
