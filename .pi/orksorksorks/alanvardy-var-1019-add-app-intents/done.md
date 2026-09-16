# Done

- **Branch / head SHA**: `alanvardy-var-1019-add-app-intents` @ `3995069`
  (`review: singular dialogues, blank-total coverage, EOF newlines`)
  - Review commit `3995069` on top of implementation head `1fc623a`
    (`docs: record VAR-1019 implementation summary`) and phase commits
    `f13f59f`/`0999034`/`35fb150`/`459be21`. Rebase was clean (no conflicts).
    Pushed with `--force-with-lease`.

- **Mechanical checks**: all green, no warnings.
  - `make test-unit` → **263 tests / 36 suites passed** (was 259; +4 review tests).
  - Full gate `bash scripts/test.sh` → **`gate: ok`**
    (`make build` → headless `.simulator_id` pre-boot → `make test` →
    `make build-mac` → `make watch-build` → 17 shell tests → `shellcheck`).
  - `python3 -m json.tool CheckStitch/Localizable.xcstrings` → valid JSON.

- **Review outcome**: one fresh-context `reviewer` (all five Swift angles:
  concurrency/Sendable, App Intents correctness, error handling, API design,
  architecture/conventions) plus parent cross-check. **No blockers.**
  - **Fixes worth doing now — applied**:
    1. Trailing newline added to `CheckStitch/Intents/ListChecklistsIntent.swift`
       and `CheckStitchTests/ListChecklistsIntentTests.swift`.
    2. `midLoopThrowTotalExcludesBlankItems` added to
       `ChecklistRemindersTests` — pins that `.partiallyCreated.total` excludes
       blank items (the loop predicate).
  - **Optional improvements — applied** (user chose `[2]`):
    3. Singular dialogue variants so Siri never says "1 reminders" / "1
       checklists": `RunChecklistDialogue` count==1 → "Created 1 reminder for
       %@." and `ListChecklistsDialogue` count==1 → "You have 1 checklist: %@.",
       with the two new keys added to `Localizable.xcstrings` across all six
       languages (en/de/es/fr/ja/zh-Hans) and to `LocalizationFixtures`.
       `created(count: 0)` and ≥2 still use the existing plural keys.
    4. `entitiesForIdentifiersReturnsStoreDisplayOrder` added to
       `ChecklistEntityQueryTests` — pins the return-order contract.
    5. TOCTOU note added at the `accessStatus()` pre-check in
       `RunChecklistIntent.perform()` (revocation between pre-check and
       `create` can still prompt; accepted, matches the SingleThread reference).
  - **Optional improvements — declined, with reason**:
    - `.created(count: 0)` wording ("Created 0 reminders…"): grammatically
      correct and a product-copy decision; left as-is.
    - Merging the intent `.permissionDenied` dialogue with Core
      `errorMessage`: they deliberately differ (Siri guidance vs UI alert); a
      merge would change tested UI text.
    - Reviewer's suspected "missing comma" in `CheckStitchShortcuts.swift`:
      **not a defect** — `@AppShortcutsBuilder` newline DSL. Do not add a comma.

- **Remaining manual items** on a real/signed build (from `plan.md`):
  - `make build-mac-signed`; confirm both `Run Checklist` and
    `List My Checklists` appear in Shortcuts.app.
  - Say "Run Groceries in CheckStitch" → items appear in the destination list
    with title/notes/due date; Siri speaks the count.
  - Reset Reminders permission (never asked) → the "open CheckStitch…" line and
    **no system prompt**.
  - Delete the destination list mid-run → Siri says "Created N of M …"; the
    in-app alert shows counts + reason.
  - "List my checklists in CheckStitch" → names in app order (and the singular
    line for exactly one); empty-state line with none; app does not open.
  - `bash scripts/run-devices.sh` end-to-end on a device.