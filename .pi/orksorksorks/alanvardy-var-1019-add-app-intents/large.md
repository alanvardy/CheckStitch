# Task

Add Siri/App Intents to CheckStitch so users can drive the app hands-free. Two
intents:

1. **Run Checklist** — takes a checklist as its one parameter (an `AppEntity`
   so Siri lets the user pick from their saved checklists by name) and creates
   all of that checklist's items as Reminders using the settings already stored
   on the checklist itself.
2. **List My Checklists** — a query intent with no side effects that surfaces
   the user's saved checklists.

Key behaviors to design for:

- **Partial creation failures**: if only some items get created, surface a
  clear error telling the user exactly what happened and that the full list was
  not created — never a silent or ambiguous state.
- **Reminders permission**: check authorization status explicitly *before*
  attempting creation and fail cleanly with a clear message if not granted
  (there is no UI moment to prompt mid-intent).
- **Target list deleted/renamed** outside the app: handle gracefully.
- **Per-item detail mapping**: due dates/notes and any per-item settings must be
  fully mapped onto each created reminder so nothing is silently dropped.
- No intent parameters beyond the checklist selector for now (per-run
  customization parameters are deferred).

Note: this repo already has a draft PR (#47) whose branch matches this ticket.

## Why LARGE

UNKNOWNS + NEW_SURFACE + CONVENTION_RISK. This introduces the App Intents
framework (new API/subsystem) and threads through shared CheckStitchCore code
(the checklist creator and EventKit seam); it raises multiple open design
questions — AppEntity parameter/discovery wiring, partial-failure error
shaping, pre-intent permission handling, and deleted/renamed target-list
recovery — each needing research and a design decision.
