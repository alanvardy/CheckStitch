# Task

The iPad "edit checklist" screen (the `ChecklistDetailView` pushed into the
root `NavigationStack` as the `UUID` navigation destination, plus its
`ItemEditView` item subscreen) currently spans the entire screen width. Make it
narrower on iPad, constrained like the Settings screen.

The Settings screen is narrow because it is shown as a `.sheet(...)` on
`ContentView`. The checklist-edit screen is instead a full-screen navigation
destination, so it renders edge to edge. Constrain the edit screen's content
width on wide (iPad) viewports so it "hugs" a centered column the way Settings
does, rather than stretching full-width.

Existing precedent to follow: the main list already caps its content with
`ChecklistWidth.maxContentWidth(viewportWidth:)` — `min(340, viewportWidth * 0.6)`
(`ChecklistWidth` enum in `CheckstNeeds.ContentView.swift`). Applied via
`.frame(maxWidth: ...)` wrapped around the content, using a `Geometry`
(`@Environment(\.geometry)`) to read `viewportWidth`. Mirror that treatment on
the checklist-edit screen so iPad gets a centered narrower pane while iPhone
stays essentially full-width (the `min(340, ...)` already hugs narrow screens).

Verify with `make build` / `make build-mac` (WARNINGS_AS_ERRORS is on) and the
full `bash scripts/test.sh` gate before committing.

## Why SMALL
Single module (app-target views only), ≤~5 files, follows the existing
`ChecklistWidth.maxContentWidth` cap already proven on the main list. No
schema, no new subsystem, no shared/convention code, no design sign-off — the
Settings/`maxContentWidth` pattern dictates the approach. Zero unknowns; tests
needed are few and local (a headless assertion on the width constant, and only
if the width math changes).

## Key files
- `CheckStitch/ContentView.swift` — `ChecklistWidth.maxContentWidth` helper and
  how the main list applies the `.frame(maxWidth: ...)` cap; the `.sheet` that
  makes Settings narrow.
- `CheckStitch/ChecklistDetailView.swift` — the "edit checklist" screen body
  (its `Form`) needing the width constraint.
- `CheckStitch/ItemEditView.swift` — the item-edit subscreen, if it should get
  the same narrowing.