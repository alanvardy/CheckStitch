# Task

Checklist names must be unique so the user can tell checklists apart. When creating or renaming (editing) a checklist in the app, verify the new name does not collide with any other checklist's name before allowing the save; if it collides, do not save and show the user a clear error. All work happens in the app target (`CheckStitch/`) — the active store-based flow, not the legacy `CheckStitchCore` view model (which the app target no longer references).

Details / expected behavior:
- Validation belongs in `ChecklistStore`: reject a `create()` (default name `"New checklist"` or a typed name) and a `rename(id:to:)` whose target name already belongs to another checklist (exclude the checklist being renamed). Compare case-insensitively on trimmed names; the error must cover both creation and rename paths.
- On rejection, the checklist is not created/renamed (no partial state), and the UI (ContentView for create, ChecklistDetailView for rename) surfaces a clear, user-visible error (e.g. a `.alert` — none exists yet, so add one following SwiftUI conventions).
- No persistence-format change: `ChecklistStore` stays in-memory + debounced `checklists.v1` UserDefaults save; validation is purely app-layer on the existing `checklists` array.

Follow the existing pattern: `store.create()` / `store.rename(id:to:)` are the two mutation points; `ChecklistDetailView`'s `TextField("Name")` is bound into the rename path via `nameBinding`.

## Why SMALL

Single module (`CheckStitch/`, ≤~3 source files + 1–2 test files); approach known (uniqueness check on the in-memory array at the two store mutations, alert on conflict); no schema/migration (UserDefaults JSON payload untouched); no new subsystem or shared/convention code; no design sign-off needed; tests are few and local to `ChecklistStoreTests`.

## Key files

- `CheckStitch/ChecklistStore.swift` — `@Observable` store; `create()` and `rename(id:to:)` are the only mutation points; add the uniqueness check here.
- `CheckStitch/ContentView.swift` — sole screen; triggers `store.create()`; likely host for the create-conflict error.
- `CheckStitch/ChecklistDetailView.swift` — edit screen; `TextField("Name")` → `store.rename(...)`; host for the rename-conflict error.
- `CheckStitchTests/ChecklistStoreTests.swift` — XCTest, `@MainActor`, per-test `UserDefaults(suiteName:)`; the natural home for create/rename uniqueness tests (happy + duplicate paths).
- Note: a draft PR (#23) with this ticket's title already exists on the branch and the worktree has an unrelated deleted file (`DELETEME`) — reconcile before committing.