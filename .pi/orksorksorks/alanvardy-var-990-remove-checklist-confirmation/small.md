# Task

Add a confirmation dialog to the checklist detail screen: when the user hits the "Remove Checklist" button, show a confirmation asking whether they really want to remove the checklist, and only delete it if they confirm.

Per the Linear ticket VAR-990: *"Add a confirmation dialog confirming whether the user wants to remove a checklist when hitting 'Remove Checklist'"*. Note the direction: the dialog is being **added** (the branch slug reads like "remove the confirmation", but the ticket is explicit — add the confirmation). The current behavior deletes immediately with no prompt; the ask is to gate deletion behind a confirmation.

Implementation shape (approach is known — mirror the existing dialog pattern at `CheckStitch/ChecklistDetailView.swift:80-84`, the "Name already in use" `.alert`):

- The "Remove Checklist" button is a `Button(role: .destructive)` at `CheckStitch/ChecklistDetailView.swift:47-54`; its action is `isRemoving = true; store.delete(id: checklistID); dismiss()`.
- Gate that action behind a confirmation dialog (`.confirmationDialog` or `.alert` — pick the one that fits the existing pattern best), so deletion only happens on confirm; on cancel, do nothing. A destructive confirmation is the natural fit.
- `store` is `@Environment(ChecklistStore.self)`; `ChecklistStore.delete(id:)` (`CheckStitch/ChecklistStore.swift:184-189`) is the mutation point and should **not** change — no store-level delete-confirm API is implied or wanted.
- Keep the existing accessibility identifiers style and localization conventions (`"Remove Checklist"` is already in the string catalog; reuse existing strings where possible, add localized keys only if the dialog needs new copy).

Tests: cover the new behavior with few, local tests (e.g. a ViewRender-style Swift Testing suite under `CheckStitchTests/` mirroring `ViewRenderTests.swift`). Store-level delete tests in `CheckStitchTests/ChecklistStoreTests.swift` are unchanged — the store does not change.

Verify with `make test-unit` before the full `bash scripts/test.sh` gate.

## Why SMALL

Single module (app target), 1–3 files, follows the existing dialog pattern, 0 unknowns; no schema/migration, no new subsystem, no shared/convention code; no design decision or sign-off needed; tests few and local.

## Key files (from recon)

- `CheckStitch/ChecklistDetailView.swift` — "Remove Checklist" button (`:47-54`), `isRemoving` state (`:21`), existing `.alert` pattern to mirror (`:80-84`, accessibility id `renameNameConflictButton`).
- `CheckStitch/ChecklistStore.swift` — `delete(id:)` (`:184-189`); read-only reference, do not change.
- `CheckStitchTests/ViewRenderTests.swift` — existing view render-test pattern for the new test suite.
- `CheckStitchTests/ChecklistStoreTests.swift` — existing delete tests (`testDeleteRemovesOnlyTarget`, `testDeleteUnknownIDIsNoOp`); unchanged.
- `CheckStitch/Localizable.xcstrings` (via `LocalizationFixtures.swift:41`) — "Remove Checklist" already localized.
- No watchOS involvement: `CheckStitchWatch` has no removal affordance.