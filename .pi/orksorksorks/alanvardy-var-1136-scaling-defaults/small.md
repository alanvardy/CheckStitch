# Task

The ticket title is "Scaling defaults" and the description reads "Scaling should be fixed and set to 1 by default." This is a configuration/default fix to ensure the Scaling mode defaults to `fixed` (rather than `prompt`) and the scaling factor defaults to `1` when a checklist is created. It should verify the current defaults in `Checklist` initialization, the `Scaling` type, and the UI/creation paths (`ChecklistOptionsView`, `ChecklistStore.create`, and the intent/creator entry points), and correct any place where a newly-created checklist does not start with `.fixed(1)`.

## Why SMALL
This is a localized fix to default initialization values in existing model/UI code. It meets all SMALL criteria: single module, ≤~5 files, 0–2 unknowns (the defaults already exist and just need confirming/fixing), no schema or migration, no new subsystem/integration, no design sign-off, and only local test updates are needed.

## Key files (if the recon found any)
- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` — `Checklist.init(scaling: Scaling = .fixed(1))` and the `Scaling` enum
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift` — `create(name:)` and `create(name:itemTitles:)` which create new checklists
- `CheckStitch/ChecklistOptionsView.swift` — the Scaling mode picker and factor field (only shown when not `.prompt`)
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift` — `ChecklistScaling.resolve` which treats `multiple == 1` as no-op
