# Task

Make a numbered checklist's created reminder titles sort correctly by title
when the checklist has more than 9 non-blank items.

The numbering policy lives in one seam, `ChecklistTitleNumbering.title(_:position:numbered:)`
in `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`, which today
produces `"<position>: <title>"` unconditionally (e.g. `1: Milk`, `10: Eggs`).
Because Reminders sorts these strings lexically, `10:` sorts ahead of `2:`.

Change the policy so that when a list has more than 9 non-blank items, single-digit
positions are zero-padded to two digits (`01:`…`09:`), so the titles sort
numerically. Keep single-digit positions unpadded (`1:`…) when the list has at
most 9 non-blank items, and preserve the current behaviour when numbering is
disabled (`numbered == false` → title unchanged).

Implementation must thread the decision into the policy seam, following the
existing pattern: it currently receives just `position` and `numbered`, so pass
the effective item count (or a pad-width derived from it) from the caller. The
"effective" count is the count after blank items are dropped, matching how
`position` is already assigned (`ChecklistCreator.create` and the app-side
`ChecklistReminders` both drop blank titles before numbering). Keep the format
in exactly the one `ChecklistTitleNumbering` seam — do not duplicate the
padding logic at either call site.

The gate is `./scripts/test.sh` (unit suites run via `make test-unit`).

## Why SMALL

Single localized change to an existing, single policy seam plus its two
mirroring call sites; approach is known (no schema, no new subsystem, no design
decision — the ticket states the exact behaviour); few local tests covering the
happy paths (≤9 vs >9 items, numbered on/off).

## Key files

- `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift` —
  `ChecklistTitleNumbering` seam + `ChecklistCreator.create` call site.
- `CheckStitch/ChecklistReminders.swift` — app-side mirror call site.
- `CheckStitchTests/ChecklistCreatorTests.swift` — existing numbering tests
  (prefixNumbers cases) to extend.
- `CheckStitchTests/ChecklistRemindersTests.swift` — app-side numbering tests
  to extend.