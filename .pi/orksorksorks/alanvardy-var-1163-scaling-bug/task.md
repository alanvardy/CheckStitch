# Task

The `((n))` scaling marker (e.g. `((2))`) is not being resolved when a run uses
a scaling factor of 1, so the reminder title keeps the literal brackets instead
of becoming `2`. This is reported "with prompt scaling" — a Prompt-mode
checklist whose confirmed/remembered factor is 1 (the default for a new
checklist) runs without removing the brackets.

The marker-resolution seam `ChecklistScaling.resolve(_:multiple:)` in
`CheckStitchCore` explicitly returns text unchanged when `multiple == 1`,
contradicting the product help text ("The brackets are removed"), while a unit
test (`multipleOneIsAFastPath`) pins that unchanged behavior. The ticket needs
the intended semantics resolved and the marker resolution (and its
tests/callers) made consistent.
