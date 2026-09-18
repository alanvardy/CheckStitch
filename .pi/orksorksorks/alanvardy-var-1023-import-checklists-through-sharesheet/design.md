# Design Discussion

Ticket: VAR-1023 — import checklists through the Share Sheet.
Scope: one ticket, one PR, all work on the main ticket (no child tickets).

## Current State

- **File reception today is user-picked only.** The single inbound path is
  `.fileImporter(allowedContentTypes: [.json])` (`CheckStitch/ContentView.swift:178-183`)
  → `importExportVM.importFile(at: url)`, which does a security-scoped read
  (`startAccessingSecurityScopedResource` / `defer stop…`,
  `CheckStitch/ChecklistImportExportViewModel.swift:67-85`).
- **There is no OS share/open seam.** No `onOpenURL`, no `CFBundleDocumentTypes`,
  no `application(_:open:)`, no share extension; `CheckStitch/AppDelegate.swift`
  only sets appearance/orientation (`:10-64`) and re-clamps macOS window frames
  (`:71–`). `CheckStitch/ChecklistExportDocument.swift:17-24` declares a
  `FileDocument` read path that is explicitly never used. The only OS entry
  surface is Siri/Shortcuts AppIntents (`CheckStitch/Intents/`).
- **Import inserts immediately and wholly.** `ChecklistImportSession.prepare(data:)`
  (`CheckStitch/ChecklistImportSession.swift:60-102`) classifies via
  `ChecklistCodec.classify` (`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:395-424`),
  normalises migratable v1–v3, then loops *every* checklist in the file:
  non-conflicting → `store.importInsert`, name-conflicting → FIFO `pending`.
  There is no selection step — all-or-nothing per file.
- **Conflict handling is FIFO, one dialog at a time.** Replace / Keep Both /
  Keep Existing (`ContentView.swift:186-192`; `ChecklistImportSession.decide(_:for:)`
  `:106-119`; VM `advanceConflict()` `:114-117`).
- **Import writes fresh local identity** — new checklist/item UUIDs, `revision: 1`,
  stamps `now()`, drops `destinationListIdentifier`
  (`CheckStitch/ChecklistStore.swift:181-206`), name collisions detected by
  trimmed case-insensitive `sameName` (`:283-286`).
- **The one multi-select precedent is the export sheet** —
  `CheckStitch/ExportChecklistsView.swift`: `@Binding var selection: Set<UUID>` (`:12`),
  checkmark rows (`:28-38`), pure `static func toggled(_:id:)` (`:16-19`),
  `canExport = !selection.isEmpty` (`:15`), `exportSelection` owned by the VM
  (`ChecklistImportExportViewModel.swift:22`). **No positive import feedback exists** —
  errors are alerts bound to VM state (`ContentView.swift:138-144`).
- **Wire format** is JSON `ChecklistEnvelope` v4 (`Checklist.swift:323-369`),
  exported by `ChecklistExport` as `CheckStitch-yyyy-MM-dd.json`
  (`CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift:22-32`).
- **Build facts that constrain us:** app target is `SDKROOT = auto` /
  `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, iOS 18.7,
  `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_*` settings and **no
  `INFOPLIST_FILE`** (`CheckStitch.xcodeproj/project.pbxproj:501-528`). All
  compiling gate legs run with warnings-as-errors.

## Desired End State

A `.json` checklist export that arrives by email (or Files, or any share source)
can be sent to CheckStitch from the **Share Sheet / Open In**, and CheckStitch
then shows a **selection screen listing the checklists inside the file**; only
the ticked ones are imported into the `ChecklistStore`. Unticking a conflicting
checklist means no conflict dialog for it; cancelling means the store is
untouched.

Flow:

```
Mail attachment / Files / share sheet
  → "Copy to CheckStitch" (CFBundleDocumentTypes) or Open In
  → application(_:open:options:) [iOS/macOS AppDelegate]  ─┐
  → .onOpenURL at the SwiftUI root                        ─┴→ SharedImportInbox.receive(url:)
  → ContentView consumes pending file (also after cold start)
  → importExportVM.importFile(at:) → session.stage(data:)   [no store writes]
  → ImportSelectionView (checkmark rows, all selected)  … Cancel → discard(), store untouched
  → session.commit(selectedIDs:) → importInsert + FIFO pending (selected only)
  → existing conflict dialog → existing checklist list
```

Correct when: (1) sharing a CheckStitch JSON from Mail on a real iPhone offers
CheckStitch and lands on the selection screen; (2) only ticked checklists appear
in the list afterwards; (3) cancel and empty selection leave the store byte-identical;
(4) conflicts are raised only for ticked checklists; (5) a non-CheckStitch JSON
still fails with "This file isn't a CheckStitch export."; (6) the existing
in-app picker behaves identically to a share arrival.

## Patterns to Follow

- **Security-scoped read, unchanged**: keep the `startAccessingSecurityScopedResource`
  / `defer stop…` pair around the only `Data(contentsOf:)`
  (`ChecklistImportExportViewModel.swift:69-76`). Do not introduce a second read path.
- **Validation lives in the codec/session, never in a receive layer**: the
  share seam must only produce `Data` + a display name; `.unreadable` /
  `.unsupportedVersion` stay `ChecklistImportError` thrown from the session
  (`ChecklistImportSession.swift:6-22, 98-100`).
- **Checkmark multi-select pattern**: copy `ExportChecklistsView`'s shape —
  `Set<UUID>` binding, pure `toggled(_:id:)`, `checkmark.circle.fill` / `circle`,
  confirm disabled while empty (`ExportChecklistsView.swift:12-45`). Prefer
  extracting a generic `ChecklistSelectionView(title:rows:selection:onConfirm:)`
  used by export and import rather than a near-duplicate.
- **VM owns presentation state, views stay declarative**: sheet flags and
  selection sets belong on `ChecklistImportExportViewModel`, bound from
  `ContentView` (as `exportSelection` is, `ContentView.swift:192-197`).
- **Store mutation goes through store methods**: `importInsert` /
  `importReplace` (`ChecklistStore.swift:181-220`) — never write `checklists`
  directly, so tombstone/sync logic keeps holding.
- **Errors surface as root alerts bound to VM state** (`ContentView.swift:138-144`);
  reuse `importErrorMessage` + `clearImportError()` rather than a new channel.
- **App-target placement**: `ChecklistImportSession`, the view model and
  `ChecklistExportDocument` live in `CheckStitch/`; only envelope/codec/export
  types live in `CheckStitchCore`. Keep selection/session work in the app target
  so the macOS-hosted unit suites can `@testable` it as today.
- **Tests**: Swift Testing `struct` + `@Test`/`#expect`, `@MainActor` on suites
  touching the store/VM, behaviour-named functions, fakes in
  `CheckStitchTests/TestFixtures.swift`. New files under `CheckStitch/` need no
  `project.pbxproj` change (`PBXFileSystemSynchronizedRootGroup`).
- **Patterns NOT to follow**: (a) the `ChecklistExportDocument` read path — a
  declared-but-dead `FileDocument` seam; don't imitate it for reception.
  (b) A share **extension target**: this project's `project.pbxproj` is
  hand-authored, and a new target drags in a scheme, gate legs, warnings-as-errors,
  provisioning and a second process touching the store — rejected here.

## Design Decisions

1. **Reception = document-type registration + app-delegate open**, not a share
   extension. Add a small `CheckStitch/Info.plist` with `CFBundleDocumentTypes`
   (`LSItemContentTypes = [public.json]`, `CFBundleTypeRole = Viewer`,
   `LSHandlerRank = Alternate`) and `LSSupportsOpeningDocumentsInPlace = true`,
   wired via `INFOPLIST_FILE = CheckStitch/Info.plist` on the app target's two
   configurations while `GENERATE_INFOPLIST_FILE = YES` stays on (generated keys
   merge over the file). No new target, no new scheme, no new gate leg; iOS and
   macOS reception come from one plist and one seam.
2. **Dual hook, single funnel.** File URLs are delivered to
   `application(_:open:options:)` in the existing iOS/macOS app delegates *and*
   (scene-based delivery) to `.onOpenURL` on the SwiftUI root. Both call one
   idempotent `SharedImportInbox.receive(url:)` (dedupe on last-received URL);
   the inbox holds a `pending` file so a cold-start arrival survives until
   `ContentView` appears and consumes it.
3. **Selection gates the store, not Reminders.** Ticked checklists are imported
   into the `ChecklistStore` with fresh identity; running them into Reminders
   stays the existing per-row action. No destination resolution, no EventKit
   permission prompt and no partial-failure UX in the import path.
4. **Stage/commit split in `ChecklistImportSession`.** `prepare(data:)` becomes
   `stage(data:)`: decode + migrate + expose `candidates` (id = the file's
   checklist UUID, `conflicting` filled from a read-only `store.conflictingChecklist(named:)`
   for display) and touch **nothing** in the store. New `commit(selectedIDs:)`
   walks the staged checklists in **file order**, filtered by selection, and only
   then does `importInsert` / FIFO `pending` — re-checking the conflict at commit
   time so the commit decision is authoritative. `discard()` drops the staged
   file. `ImportSummary` and `ChecklistImportError` are reused as-is.
5. **One pipeline for both entry points.** The in-app `.fileImporter` and share
   arrivals both land in `importFile(at:)` and both show the selection sheet, so
   "only those are imported" holds everywhere and there is a single set of tests.
   `ChecklistImportSessionTests` / `ChecklistImportExportViewModelTests`
   expectations change from import-all to stage→select→commit; that rewrite is
   part of this ticket.
6. **Selection defaults to all ticked, Confirm required.** Mirrors
   `ExportChecklistsView` (all rows start selected, confirm disabled when empty,
   `canImport: Boolean`). Cancel/Swipe-away calls `discard()` and shows no
   success or error UI — the store is simply unchanged.
7. **Conflicts stay FIFO and per-checklist.** After commit, `advanceConflict()`
   presents the existing dialog for the first pending *selected* checklist;
   unselected conflicting names are never enqueued.
8. **Format stays `.json`.** Only `public.json` is accepted; exports are
   unchanged (`CheckStitch-yyyy-MM-dd.json`, `ChecklistExport.swift:22-32`). No
   custom UTI, no `UTExportedTypeDeclarations`, no filename change, so existing
   files and `ChecklistExportTests` filename assertions are untouched.
9. **Verification bar.** Unit tests for stage/commit/selection (happy + sad:
   empty selection, cancel, unselected conflict, unreadable/unsupported throw
   before any sheet), a `scripts/tests/run.sh` shell assertion that the source
   Info.plist carries `CFBundleDocumentTypes` and that both app-target configs
   set `INFOPLIST_FILE`, a built-plist dump
   (`plutil -p DerivedData/…/CheckStitch.app/Info.plist`) as an implementation
   step, and a final on-device manual share-from-Mail check via
   `bash scripts/run-devices.sh`. No closing on static evidence alone.

## What We're NOT Doing

- No share **extension** target, no new `PBXNativeTarget`/scheme, no App
  Group file inbox and no extension-side store access.
- No custom UTI, no `.checkstitch` extension, no change to export filenames or
  wire format, no v5 envelope.
- No import-time Reminders creation, no destination picker in the import flow,
  no "Import & Run" combined action.
- No positive import success toast/HUD (out of scope; noted as a gap, not fixed).
- No batch/whole-file conflict resolution UI (the FIFO dialog stays).
- No macOS share-extension or Services-menu work; macOS reception is only the
  document-type/Open-In leg that comes free with decision 1.
- No multi-file share handling (one file at a time; a second arrival within a
  session replaces the staged file).
- No child tickets — all work lands on VAR-1023.

## Open Risks

1. **`INFOPLIST_FILE` + `GENERATE_INFOPLIST_FILE = YES` merge behaviour.** Believed
   supported (file as base, generated keys merged); must be proven by compiling
   and dumping the built plist. If it fails, fallback is `INFOPLIST_KEY_*`
   settings for the scalar keys plus a generated-file post-process — both are
   implementation-phase fallbacks, not design changes.
2. **Share-sheet presence depends on the provider's UTI.** Mail/Files usually tag
   `.json` as `public.json`; a provider offering `public.data` will not match the
   doc type. Mitigation if the on-device check shows CheckStitch missing: widen
   `LSItemContentTypes` to include `public.data` and let the codec reject
   non-CheckStitch payloads with the existing message. Widen only if needed —
   `public.data` would advertise CheckStitch for every file.
3. **Two delivery hooks double-fire or arrive pre-root.** Mitigated by one
   idempotent funnel + a `pending` slot; needs a regression test on the inbox
   (`receive` twice with the same URL yields one consume; a cold-start arrival is
   still consumable once `ContentView` appears).
4. **Existing test suites encode import-all semantics.** `ChecklistImportSessionTests`
   and `ChecklistImportExportViewModelTests` must be rewritten, and the FIFO test
   (`decide` + `await Task.yield()`) now needs a commit step first; a missed
   rewrite shows up as gate failures rather than silent behaviour change.
5. **`.fileImporter` on macOS was already reported as flaky when nested in a
   sheet** (research Q4 note). The selection sheet must be presented from the root
   `ContentView`, alongside the existing import/export alerts, not nested in
   `SettingsView`'s sheet.