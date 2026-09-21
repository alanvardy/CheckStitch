# Task

In light mode the main screen shows a mix of blue and black borders around the
checklist cards. Make the borders on the main screen black.

Context: the main checklist screen (`CheckStitch/ContentView.swift`) draws the
card/checklist borders with `.stroke(.tint, lineWidth: 2)` — `.tint` resolves
to the blue accent color — in a handful of places (roughly lines 293, 321,
378, 402, 495). In light mode this blue clashes with the black glyphs/labels
and the `CardPlate` chrome. `CardPlate.swift` already centralizes
per-`ColorScheme` styling decisions (`plateFill`, `iconPlateFill`,
`iconForeground`, `cornerRadius`) that are asserted headlessly in unit tests.

Change the main screen's stroke/border color (either swap the `.stroke(.tint, …)`
calls to black, or thread the choice through `CardPlate` to follow the existing
colorScheme pattern) so that in light mode the main-screen borders are black.
Keep dark mode legible — if black-on-black would hurt dark mode, gate the
change on `colorScheme == .light` following `CardPlate`'s pattern. Verify with
`make test-unit` (add/extend a headless assertion if the change is threaded
through `CardPlate`), then the full `bash scripts/test.sh` gate.

## Why SMALL
Single module (the main screen view + its CardPlate style), local UI color
change following the existing per-scheme styling pattern; no schema, no new
subsystem or shared/convention code, no design sign-off required (the ticket
states the desired end state), tests few and local.

## Key files
- `CheckStitch/ContentView.swift` — the `.stroke(.tint, lineWidth: 2)` border
  calls on the main screen (~lines 293, 321, 378, 402, 495).
- `CheckStitch/CardPlate.swift` — existing per-`ColorScheme` styling pattern to
  follow if the color is centralized.
- `CheckStitchTests/` — headless assertions over `CardPlate` decisions.