# Task

On the Apple Watch, opening a checklist (tapping a checklist in
`WatchChecklistListView`) shows the items screen
(`WatchChecklistDetailView`) with a "Create reminders" button pinned to the
bottom via `.safeAreaInset(edge: .bottom)`. The bug: the item rows scroll
over/under the button instead of stopping cleanly above it. Fix the watch
screen so (1) the items list is constrained to be above the pinned button
(rows never overlap it when scrolling), (2) the "Create reminders" button is
blue, and (3) the "Checklists" title bar in `WatchChecklistListView` is blue
(the `.navigationTitle("Checklists")`).

Scope is the watch target only (`CheckStitchWatch/`); do not change the
phone/macOS/`CheckStitchCore` surfaces. Per the `swiftui-sdk` skill, the
compiler is the oracle for which SwiftUI API (e.g. button foreground/tint,
list content padding vs. the bottom safe-area inset) achieves the
constraint and colouring — `make watch-build` / `make build` to verify.
Colours ideally come from an existing SwiftUI semantic/style (e.g. accent/tint)
rather than a hardcoded literal where a precedent exists.

## Why SMALL
Localized single-screen watchOS UI fix (2 files, one module, existing SwiftUI
pattern); no schema, no new subsystem, no shared/convention risk, no design
decision, no test infrastructure — the compiler is the sole gate.

## Key files
- `CheckStitchWatch/WatchChecklistDetailView.swift` — the items list + the
  pinned "Create reminders" `Button` in a `.safeAreaInset(edge: .bottom)`;
  constrain the items above the button and colour the button blue here.
- `CheckStitchWatch/WatchChecklistListView.swift` — make the "Checklists"
  `.navigationTitle` blue.