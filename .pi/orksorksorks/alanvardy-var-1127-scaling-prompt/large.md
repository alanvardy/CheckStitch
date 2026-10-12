# Task

Add a third scaling option, "Prompt", alongside the existing numeric scaling
options on a checklist. When a checklist's scaling is set to Prompt, running
it must ask the user for a number and scale the created reminders by that
number. This applies both when the checklist is run from inside the app and
when it is run via the App Intent.

## Why LARGE

Matched triggers: **SCHEMA**, **CONVENTION_RISK**, **CROSS_CUTTING (unknown
ordering)**, **UNKNOWNS**, **DESIGN_SIGN-OFF**.

The decisive signal: the only stored scaling state is `Checklist.multiple: Int`
(clamped `1...99`), so representing "prompt" requires a new stored
representational field/enum that must survive JSON codec encode/decode,
`ChecklistStore` setter + save, LWW sync merge, duplicate, export/import and
iCloud compatibility with already-persisted checklists — a data-model change
threaded through storage *and* the run seam *and* the intent interface.

Supporting evidence for the other triggers:

- **UNKNOWNS / DESIGN_SIGN-OFF** — `RunChecklistIntent` has
  `openAppWhenRun = false` and currently never prompts for anything
  (permissions are status-only, errors are thrown as `invalidMultiple`).
  There is no existing App Intents interactive-input pattern in the repo, so
  the intent-side prompt (native App Intents parameter/dialog vs. returning a
  request-to-open vs. error) is an open design question needing a spike. The
  in-app side also has no numeric input in the run path today.
- **CROSS_CUTTING, unknown ordering** — the change touches data
  model/storage (`Checklist`, `ChecklistStore`, `ChecklistMerge`), UI
  (`ChecklistDetailView` scaling editor, `ContentView` run flow, watch
  preview), and platform/contract targets (`CheckStitch`, `CheckStitchCore`,
  `CheckStitchWatch`, App Intents), with no existing pattern that dictates the
  layering and sequence.
- **CONVENTION_RISK** — the two consum points
  (`ChecklistRunViewModel.createReminders(for:)` and `RunChecklistIntent.perform()`)
  both funnel into `ChecklistReminders.create(..., multipleOverride:)`; the
  semantics of Prompt mode versus the existing per-run `multipleOverride`
  parameter (and any widget/config intents) need a decision, and the
  persistence format must stay backward compatible.

Related sibling branches exist (`alanvardy-var-1128-add-prompt-to-destination-checklist`,
`alanvardy-var-809-scaling-templates`) — unmerged, a possible overlap to
check during research. Draft PR #98 contains no relevant diff on this branch.
