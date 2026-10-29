# Task

A `((n))` marker such as `((2))` is not resolved when a run uses a scaling
factor of 1: the reminder title keeps the literal `((2))` instead of becoming
`2`. This is reported as happening "with prompt scaling" — a Prompt-mode
checklist whose confirmed/remembered factor is 1 (the default for a new
checklist) runs without removing the brackets. The marker-resolution seam,
`ChecklistScaling.resolve(_:multiple:)` in `CheckStitchCore`, explicitly
returns text unchanged when `multiple == 1`, contradicting the product help
text ("The brackets are removed"), while a unit test
(`multipleOneIsAFastPath`) pins that unchanged behavior. The ticket needs the
intended semantics resolved and the marker resolution (and its tests/callers)
made consistent.

## Why LARGE

DESIGN_SIGN-OFF + UNKNOWNS/SPEC: the documented contract, the current
`resolve` behavior (and its pinned test), and the ticket disagree, and the
ticket leaves open whether fixed-1 checklists must also strip brackets
(backward-compatible user-visible change) or only prompt-confirmed runs — a
product trade-off needing a human decision before the fix shape is known.
CROSS_CUTTING / CONVENTION_RISK reinforcing: `ChecklistScaling.resolve` is a
shared seam consumed by the core creator, the app run path, the watch detail
preview and the App Intent, so choosing a mode-aware fix threads a parameter
across those surfaces.
