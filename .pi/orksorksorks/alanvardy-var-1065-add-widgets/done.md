# Done

- **Branch / head SHA**: `alanvardy-var-1065-add-widgets` @ `7aa2403`
  (fix commit; review pipeline head `a562a2c` + fix `7aa2403`, both pushed).

- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` after the fix.
  Covers `make build` (iOS sim), headless pre-boot + `make test`,
  `make build-mac`, `make watch-build`, `make widget-build` (warnings-as-errors),
  `scripts/tests/run.sh` (26 passed, 0 failed), `scripts/l10n-check.sh` (`ok`,
  4 catalogs), and `shellcheck scripts/*.sh scripts/tests/*.sh`.
  No warnings flagged. No rebase conflicts (branch was already current).

- **Review outcome**: one bounded `reviewer` pass over the full
  `git diff main...HEAD` (32 files), plus a parent scan of the new widget/Core
  sources. **No blockers.**
  - *Applied (fix worth doing now)*: the widget collapsed `.needsAccess` and
    `.needsPurchase` into one non-runnable state and rendered the access prompt
    for both, leaving `"Open CheckStitch to buy a license"` a dead catalog key.
    Added `ChecklistWidgetRow.needsPurchase`, branched both views' copy, and
    added display-model tests. Validated with the full gate.
  - *Applied (optional improvement)*: `ChecklistWidgetLoader.load` no longer
    silently falls back to the first checklist for an unconfigured widget;
    it now renders the empty-state hint. Added
    `ChecklistWidgetDisplayModel.hasChecklists` so the hint distinguishes
    "nothing configured yet" (`Edit this widget to pick a checklist`) from an
    empty store (`No checklists`).
  - *Deferred/declined*: reviewer's "optional array/entity optionality could
    surprise" nit — verified safe at all four call sites, no action.

- **Remaining manual items** (cannot close on static evidence; see
  `.pi/orksorksorks/alanvardy-var-1065-add-widgets/implement.md` and the phase
  Manual sections in `plan.md`): all on-device/simulator widget verification is
  still outstanding — add/edit small and large widgets, confirm run buttons
  create reminders without foregrounding the app, free-run counter behaviour,
  the access-off and purchase-limit states (now with distinct copy), the
  unconfigured-widget hint, and localized widget strings on a language switch.