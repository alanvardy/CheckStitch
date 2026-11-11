# Task

On the iPhone Duo's outer (folded) screen in portrait, widen the checklist
content by halving the side padding. The change must be scoped strictly to
that device + orientation — every other screen and orientation keeps its
current layout.

## Why LARGE

UNKNOWNS (SPEC + API) with CONVENTION_RISK reinforcing.

- **SPEC / mechanism ambiguity** — "the padding" does not map to one lever:
  the list/header card width is driven by `ChecklistWidth.maxContentWidth`
  (`min(340, viewportWidth * 0.6)`, a *fraction* cap in
  `CheckStitchCore`), while literal `.padding(.horizontal, 32)` also exists on
  the list card, the iOS header row, and the empty-state card. Halving the
  literal padding would not widen the fraction-capped list card, so the fix
  shape (which lever, and how much) has to be decided before implementation.
- **No device/screen detection exists** — the repo has zero precedent for
  identifying a device or a foldable cover screen; `ChecklistWidth` only takes
  a raw `viewportWidth`. Deciding how to recognise the Duo outer screen
  (device model / `productType`, screen size, aspect ratio, size class) and
  how to pass it across the app→core seam is an open research/design item.
- **CONVENTION_RISK** — `ChecklistWidth` is a shared, test-pinned seam
  (`ChecklistWidthTests`, called from `ContentView`) and the ticket demands no
  change on other screens/orientations, so the device-conditional behaviour
  must be isolated and locked with backward-compatibility tests.

Decisive signal: the ticket names a specific device's outer screen but the
codebase has no mechanism to identify a device or cover screen, and the
"padding" it names is not the thing that drives the card's width — so the fix
cannot be one-shotted without research/design first.
