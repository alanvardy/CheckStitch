# Task

Add a destination-list selector to the edit-checklist screen so the user can
choose which Reminders list the generated reminders are created in (default:
the inbox), persisting that choice with the checklist. When a checklist is run,
if its selected destination list no longer exists, show an error and create no
reminders at all.

## Why LARGE

- **SCHEMA** — the persisted Checklist model/codec (the VAR-969 store/codec)
  gains a destination-list field, and every checklist already stored must keep
  working and default to the inbox (backward-compat/defaulting).
- **NEW_SURFACE** — the app currently only ever creates reminders in one list;
  enumerating the available Reminders lists and resolving a stable list
  identifier is a new integration in the EventKit seam.
- **UNKNOWNS** — how lists/identifiers are enumerated on this Reminders
  toolchain, how the identifier survives renames/restarts and serializes
  compatibly, and how the all-or-nothing failure (validate existence before
  creating any reminder, surface the error in the UI) should be layered.
- Also CROSS_CUTTING: data model (Checklist + codec) + UI surface (edit
  screen) + platform create flow (EventKit seam, view model/error surface).