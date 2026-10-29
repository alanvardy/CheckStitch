# Research Questions

## Context
Focus on the checklist scaling subsystem in the `CheckStitchCore` local SPM
package and its consumers in the app, Watch target, and App Intent. Of
interest: the marker-resolution seam, the scaling-factor model (fixed vs
prompt mode), every call site that resolves marker text, the tests that pin
current behavior, and the user-facing help text and localization around
scaling.

## Questions

1. How does `ChecklistScaling.resolve(_:multiple:)` transform text today —
   what is the exact marker grammar it accepts, and what output does it
   produce for `multiple == 1` versus `multiple > 1`? Include the title
   numbering sibling and the doc comments.

2. How is a checklist's scaling factor modeled and derived — the `Scaling`
   enum (`fixed` / `prompt`), `.number`, `.displayNumber`, `.isPrompt`,
   clamping and range, persistence/codable, and the legacy `multiple`
   accessor?

3. How does the run path select a multiple and thread it into marker
   resolution — the run view model (`startRun`, `confirmPrompt`,
   `perform(multipleOverride:)`), the prompt sheet, the `ChecklistReminders`
   funnel, and the App Intent's prompt resolution?

4. How do each of the marker-resolution call sites invoke it and with what
   multiple — the core `ChecklistCreator`, `ChecklistReminders`, the app
   detail view, and the Watch detail preview? Note which paths pass 1.

5. What tests and fixtures pin marker-resolution and scaling behavior —
   the resolver unit tests (including `multipleOneIsAFastPath`), funnel, run
   VM, intent, codec/import/export, and the fakes in `TestFixtures`? What
   behavior does each assert?

6. What does the user-facing scaling help text and its localization say the
   marker behavior is, and where is that text surfaced in the UI?

