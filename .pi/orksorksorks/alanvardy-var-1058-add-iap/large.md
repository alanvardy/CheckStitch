# Task

Add in-app purchases to CheckStitch: introduce a purchasable license and
require the user to purchase it after they have run 20 checklists. Running a
checklist must track a durable count, and crossing the threshold must gate the
app behind a purchase flow (in-app purchase via StoreKit 2, wired to the
`CheckStitchCore` checklist creator and the `ContentView`).

## Why LARGE

UNKNOWNS + CONVENTION_RISK + DESIGN_SIGN-OFF: in-app purchases introduce a new
technology/API (StoreKit 2) and the 20-checklist/entitlement design has many
open questions (product setup, durable run counting, restore-purchases,
unlock gating across the creator, view model and UI) touching the shared
purchasing/entitlement path with device and sandbox behavior unknowns — a
multi-phase research → design → plan → implement → review pipeline.