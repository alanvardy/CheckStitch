# Research Questions

## Context

Focus on the CheckStitch iOS app target and the CheckStitchCore SPM package:
the main content screen's layout (width caps and horizontal padding), how
viewport geometry and device/orientation traits reach the layout math, the
platform-conditional and test conventions used across the repo, and what
platform APIs exist for identifying a foldable device's cover screen.
Describe what exists today; do not propose changes.

## Questions

1. How is the checklist list card's width computed and constrained — where is
   `ChecklistWidth` defined, what does each function return, where is it
   called, and how do the resulting frame cap and the surrounding literal
   horizontal padding combine in the main screen's view hierarchy?

2. Everywhere horizontal padding is applied across the app's checklist
   screens, what are the literal values, which specific view/screen each one
   applies to, and are any of them derived from a shared constant, viewport,
   or device trait?

3. How does the app obtain viewport geometry, size classes, and orientation,
   and what is the data-flow path from the app target (ContentView,
   AppDelegate, OrientationPreference/Policy) into CheckStitchCore?

4. What platform-conditional code patterns exist in the repo (iOS vs macOS vs
   watchOS vs widget; `#if os(...)`, availability checks, target-specific
   files) and how are they structured and located?

5. How are CheckStitchCore APIs and view/layout behaviours pinned by tests —
   which suites, fixtures, `@Test(arguments:)` cases, `@MainActor` usage, and
   platform gating are used for width/padding/render assertions?

6. What iOS/UIKit APIs exist for identifying a foldable device's cover/outer
   screen and its orientation (device model / `productType` / `utsname` /
   `UIDevice`, screen dimensions, aspect ratio, scene geometry requests), and
   how is that identity accessed from Swift today?
