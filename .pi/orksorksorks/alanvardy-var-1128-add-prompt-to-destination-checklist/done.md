# Done

- **Branch / head SHA**: `alanvardy-var-1128-add-prompt-to-destination-checklist` @ `1f87b77` (pre-`done.md`; the artifact commit adds one more on top).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` — simulator build, headless pre-boot + `make test`, `make build-mac`, `make watch-build`, 26 shell tests, shellcheck. `bash scripts/l10n-check.sh` → `l10n-check: ok (4 catalogs, 185 keys, 6 languages)`. No warnings-as-errors failures. Rebase: none required (`main` is an ancestor of HEAD).
- **Review outcome**: one bounded reviewer pass over the 2670-line diff (no blockers), cross-checked with a direct scan. Two P2 findings fixed:
  - `SingleChecklistWidget`/`MultiChecklistWidget` `widgetURL(for:)` now deep-links a `.prompt` row to the run chooser only when the row is not paywalled, so a row labelled "Open CheckStitch to buy a license" no longer opens the chooser first (no gate bypass either way).
  - Removed the dead `DestinationPromptSheet.defaultIdentifier` parameter and the `ChecklistRunViewModel.destinationDefaultIdentifier` plumbing; added EOF newlines.
  - Optional/deferred: none outstanding. Localization keys and fixtures unchanged.
- **Remaining manual items** (from `implement.md`; static/test evidence covers the logic but not the installed bundle):
  - Phase 1: `make run`; open a checklist → Destination list → tap **Ask me each time**; back out, tap Run → sheet lists every Reminders list plus **Default (Inbox)**; pick one, tap Run → reminder lands in that list; re-open the picker → still **Ask me each time**.
  - Phase 2: in Shortcuts add **Run Checklist**, choose a `.prompt` checklist → run shows the list picker; delete the parameter value and run headless → the `.destinationRequired` dialog appears.
  - Phase 3: add a widget for a `.prompt` checklist → tap the tile opens the prompt sheet for that checklist; `checkstitch://` access prompts still work. Also confirm a paywalled `.prompt` tile (at the free limit) does **not** open the chooser.
  - Phase 4: `bash scripts/run-watch.sh`; tap Run on a `.prompt` checklist → **Choose a list on iPhone.**, no reminders created.
  - Phase 5: revoke Reminders access → Run a prompt checklist → permission-denied message, no empty sheet; restore access and confirm the prompt flow still works.
