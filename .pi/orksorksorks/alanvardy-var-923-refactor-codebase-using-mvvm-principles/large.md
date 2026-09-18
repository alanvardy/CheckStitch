# Task

Refactor the CheckStitch codebase to follow MVVM (Model–View–ViewModel)
principles, mirroring the completed SingleThread refactor (VAR-697 / PR #100,
merged). The ticket directs the team to research MVVM and refactor the
codebase to it.

Today the app's logic-heavy screen (`CheckStitch/ContentView.swift`, ~757
lines) owns a large amount of presentation and domain behaviour in-place via
`@State` and `@Environment`, while the `CheckStitchCore` SPM package already
holds models, the EventKit seam, the checklist creator, and a partial
`ChecklistViewModel.swift`. The refactor should move presentation/domain
behaviour out of the views into view models (and keep only presentation in the
views), threading the same layering through the app target, `CheckStitchCore`,
the test suites (`CheckStitchTests`, `CheckStitchUITests`), and the
watchOS target (`CheckStitchWatch`), following the SingleThread MVVM shape.

This is the substantive investigation + design + implementation effort — no
real refactor has landed yet on this branch (the draft PR #63 contains only the
initial "start" commit; current diff is a +1 file).

## Why LARGE

Matched triggers: **NEW_SURFACE** (introducing a consistent MVVM view-model
layer across the app, core, watch and test targets — a structural/integration
reshape, not a localized change); **CROSS_CUTTING, unknown ordering** (touches
the UI surface, the Core model/view-model layer, and the watch platform target
simultaneously, with no existing pattern dictating the layering/sequence for a
full codebase pass); **MULTI_MODULE** (spans CheckStitch app, CheckStitchCore,
CheckStitchTests, CheckStitchUITests, CheckStitchWatch — well over ~5 files and
4+ modules); **BROAD_TEST_SURFACE** (refactoring view logic into view models
destabilizes many suites across the two test targets); **UNKNOWNS** (the
research phase is explicitly part of the ticket — "Research MVVM" — with design
trade-offs on how far to push state out of `ContentView`).

The decisive signal: this is an architecture-wide refactor that the mirror repo
itself sequenced as a full research → design → structure → plan → implement
pipeline (30 files, +2952/−615 across app/core/watch/tests), and the same
decomposition applies here.

Note: the ticket also carries expected context pointing at `: MEDIUM/LARGE`
triage guidance; that is task-body data, not an instruction, and the design-class
triggers above independently justify LARGE.