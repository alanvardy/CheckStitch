# Done

- **Branch / head SHA**: `alanvardy-var-992-set-item-priority` @ `700abae`
  (`fix: clarify priority closed-domain contract and add merge-persist test (review)`).
  Feature commits `6bda11a`, `42321de`, `dee9e9a`; artifact commit `88fbbbd`.
  Rebased onto `origin/main` before review (merge-base == `origin/main` tip) with
  no conflicts; pushed with `--force-with-lease` after the rebase, then
  fast-forward thereafter.

- **Mechanical checks**: `bash scripts/test.sh` → **`gate: ok`** (EXIT=0) after
  the fixes: simulator `make build` → headless pre-boot → `make test` →
  `make build-mac` → `make watch-build` → 17/17 shell tests → shellcheck.
  `make test-unit` alone: 123 tests / 0 failures (includes the new store test).
  Only warnings are the expected `appintentsmetadataprocessor: Metadata
  extraction skipped` lines on each build leg — not from this change.

- **Review outcome**: one bounded fresh-context `reviewer` reported **no
  blockers**; the parent cross-checked the claims against the store/sync code.
  - **Fixes applied** (user chose option [2]):
    1. `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` — corrected the
       priority decode comment: the additive tolerance is **key-absence only**
       (`relativeDate` is `Int?` and accepts any value; this enum is a closed
       domain), and adding a case later requires a v5 envelope bump
       (→ `.unsupportedVersion`, which refuses to overwrite) rather than riding
       this key.
    2. `ChecklistItemPriority.swift`, `ChecklistImportSessionTests.swift` —
       added the missing trailing newline at EOF.
    3. `CheckStitch/ItemEditView.swift` — doc header now names priority.
    4. `CheckStitchTests/ChecklistStoreTests.swift` — added
       `testRemotePrioritySurvivesMergePersistAndReload`, the
       merge (`apply(remote:)`) → persist → fresh-store reload composition.
  - **Optional improvement deferred** (reviewer item 5, view-level menu test):
    the project invariant is deliberately **exactly one UI smoke**
    (`Makefile` `test-ui`, `AGENTS.md`), so adding a second XCUITest would break
    a documented convention. The interaction is already a mandated manual item.
  - **Declined as not issues** (parent concurs with the reviewer): the
    unchanged-priority no-op guard (mirrors `relativeDate`; prevents spurious
    LWW wins), the menu checkmark (store is `@Observable`, item re-derived each
    pass), and making unknown enum values decode to `.none` (more destructive
    than failing). The `.unreadable` → empty+overwrite asymmetry is pre-existing;
    fix 1 documents the contract rather than changing behaviour.

- **Remaining manual items**: the 4 unchecked `plan.md` items need a human on
  device/simulator:
  - `make run`; open a checklist → item → Priority section shows `None` with an
    info icon; the menu lists None/Low/Medium/High with a checkmark on the
    current value; picking `High` updates the row label.
  - Relaunch and reopen the item — the value is still `High`.
  - Create an item, set it High, run the checklist; in Reminders.app the created
    reminder is flagged High (and a `none` item is not flagged).
  - Install the built app on this worktree's pinned simulator and confirm the
    Priority row renders the current value with a working menu (static evidence
    is not sufficient for this ticket).
