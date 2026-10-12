# Task

Let a checklist's destination be "prompt" instead of a concrete destination, so
the user picks the destination at the moment they run the checklist rather than
when configuring it. The prompt must also fire when a checklist is run through
an App Intent / Shortcut, which means the persisted destination model, the
run-time UI, and every intent entry point have to agree on the new state.

## Why LARGE

Matched triggers: **CROSS_CUTTING (unknown ordering)**, **SCHEMA**, **NEW_SURFACE**, **DESIGN_SIGN-OFF**.

The destination is persisted model data on `Checklist` (`Checklist.swift`),
surfaced through the sync/store layer, several App Intents
(`RunChecklistIntent`, `ChecklistConfigurationIntent`,
`MultiChecklistConfigurationIntent`), widgets and the watch target — so the
ticket spans data model + UI + intent contracts with no existing pattern
dictating the layering, and the third "prompt" state is a new persisted variant
plus a new run-time surface that must work in a headless intent context.
