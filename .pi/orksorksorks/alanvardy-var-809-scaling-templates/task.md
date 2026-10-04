# Task

Add template **scaling** to CheckStitch: each `Checklist` carries a positive
integer `multiple` (default `1`), and at reminder-creation time each `((n))`
marker in an item's title/description is replaced with `n × multiple` (the
stored text is never rewritten). Add a Scaling `Stepper` (1...99) section on
the detail screen, render scaled text on read-only surfaces while editors stay
raw, and add a "×N" factor badge (only when `multiple > 1`) on rows. Extend the
`RunChecklistIntent` with an optional `multiple` override (+ `.invalidMultiple`
validation with side-effect-free ordering).

Delivery is phased: (1) setting & persistence (field + setMultiple no-op
guard/revision bump, Scaling section, codec/merge/duplicate/import/export/share,
localization baseline); (2) resolution & surfaces (pure resolution function as a
sibling of `ChecklistTitleNumbering`, both run paths wired, read-only surfaces
resolve while editors stay raw, factor badge, scale-then-prefix order); (3)
intent override (optional `multiple` param, `.invalidMultiple`, validation-first).