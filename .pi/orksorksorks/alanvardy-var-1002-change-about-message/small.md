# Task

Change the about/footer message displayed in the CheckStitch About view from
"Made with love by a lone developer" to "Made with ❤️ by a Canadian developer
🇨🇦" (VAR-1002).

The literal string currently appears in four places; update every one so the
source, the localization catalog, and the test expectations stay in sync:

1. `CheckStitch/AboutView.swift` — the in-app string rendered by the view.
2. `CheckStitch/Localizable.xcstrings` — the English source-language entry in
   the localization catalog (keyed by the same string).
3. `CheckStitchTests/AboutViewTests.swift` — two expectations asserting the
   rendered attribution and the body description.
4. `CheckStitchTests/LocalizationFixtures.swift` — the fixture feeding those
   tests.

Run `make test-unit` (fast) to verify; the full gate is `./scripts/test.sh`.

## Why SMALL

A–F all hold: single module (app target + its unit tests), ≤4 files, follows
the existing pattern of keeping source/catalog/fixtures in sync; 0 unknowns
(the new text is fully specified by the ticket); no schema, no new
subsystem, no shared/convention risk (it is a plain displayed string, not a
build format); no design decision or sign-off; the only tests touched are two
local expectations and one fixture.

## Key files

- `CheckStitch/AboutView.swift` (line 22)
- `CheckStitch/Localizable.xcstrings` (line 906)
- `CheckStitchTests/AboutViewTests.swift` (lines 16, 33)
- `CheckStitchTests/LocalizationFixtures.swift` (line 36)