Review complete. I inspected the full diff, the store, codec, import session, ContentView, localization fixtures/tests, and the design/plan fragments. No blockers confirmed; findings below.

## Review — VAR-997 (Import/Export checklists as JSON)

**BLOCKERS (must fix before merge)**
- None confirmed.

**NITS (non-blocking)**
- `CheckStitch/ContentView.swift:492-493` — bare `catch` mislabels every non-format failure (I/O, permission, read errors from `Data(contentsOf:)`) as "This file isn't a CheckStitch export."; a real read failure should not be reported as a format error. Smallest fix: distinct message or `error.localizedDescription`.
- `CheckStitch/ChecklistImportSession.swift:72-78` — doc claims "Resets prior state, so one session per file is idempotent," but the reset (77-78) runs after the decode switch, so a second `prepare()` that throws (`unsupportedVersion`/`unreadable`, 72-74) leaves a prior file's `pending`/`summary` stale. Unreachable today (`ContentView` news a session per file) — doc/behavior mismatch only.
- `CheckStitch/ContentView.swift:489` vs `522-523` — the first conflict is presented synchronously inside the `.fileImporter` callback, while subsequent ones go through `DispatchQueue.main.async` specifically to land "after the current dismissal completes." The first presentation skips that deferral; if the same presentation hazard applies, the first conflict can be lost or double-handled. Recommend routing the first presentation through the same deferred path (unverifiable without a device run).
- `CheckStitch/ChecklistImportSession.swift:66-67` — v1/v2 migration (`migrated(at:)`/`seededOrder()`) is dead work on import: every candidate funnels into `freshCopy` (`ChecklistStore.swift:178-182`), which re-identifies all sync/order state. Harmless; the branch could pass checklists through verbatim (and its doc overstates what import migration accomplishes).
- `CheckStitch/ChecklistImportSession.swift:58-96` — partial application is intended and safe (documented at 53-56; each store op is atomic and consistent, replace tombstones only on explicit decision), but confirm it as a product decision: free-name checklists from the file are committed and pushed to the cloud before the user answers any conflict, and there is no "abort whole import" — only per-conflict Keep Existing.
- `CheckStitch/ContentView.swift:503-507` — the dismissal-default branch (binding setter fires `false` → `.keepExisting`) is untested; the `choose()` paths have coverage in `ChecklistImportSessionTests` but nothing exercises the setter path itself.
- `CheckStitch/ChecklistImportSession.swift:12-13,93` (`ContentView.swift:493`) — hardcoded English messages follow the `ReminderRunOutcome.errorMessage` precedent (`ChecklistCore/ReminderDestinationTargeting.swift:66-69`), so consistent, but they surface in a localized alert on 5 locales; consider catalog keys if these remain the primary message path.
- `CheckStitch/ChecklistImportSession.swift:77-96` — conflict-resolved checklists land after all free-name imports in store order regardless of file position (cosmetic).
- `CheckStitchCore/.../ChecklistExport.swift:24-27` — `filename()`'s defaults (`Date.now`, `Calendar.current`) are exercised only by the live call site; the unit test always passes an explicit UTC calendar, so the default path is untested.
- `CheckStitch/ContentView.swift:485` / `ChecklistImportSession.swift:58` — full encode/decode of the file runs synchronously on the main actor; large libraries may jank the UI briefly (matches the app's single-threaded norm — note only).

**Could not verify**
- `DispatchQueue.main.async` (ContentView.swift:522) — API validity/availability and its ordering guarantee relative to SwiftUI modal teardown; no repo precedent (only plan.md and this diff), Swift-edition dependent.
- macOS/iOS `fileExporter`/`fileImporter` behavior on user CANCEL — if cancel delivers a `.failure`, every cancelled picker would pop a spurious "Couldn't import"/"Couldn't export" alert; needs a desktop run.
- iOS semantics of `fileExporter`/`fileImporter` and of presenting the `confirmationDialog` immediately after the importer closes (code is not platform-gated).
- `Calendar.current`/`DateFormatter` with `dateFormat: "yyyy-MM-dd"` + `en_US_POSIX` producing "CheckStitch-2026-09-14" on device (only the UTC case is pinned).
- The `./scripts/test.sh` gate and the newly added XCTest/Testing suites' pass state — not run here.

Localization verified: the 12 new `Localizable.xcstrings` keys match `LocalizationFixtures.requiredKeys` exactly, the interpolated key `"“%@” already exists."` follows the existing `\(x)` → `%@` convention (`ChecklistDetailView.swift:143` / `"Photo by %@ on Unsplash"`), and all six languages are present. Concurrency hygiene (MainActor placement, @Observable, access/stop pairing, no force-unwraps, no fatalError, no retain cycles) checks out.