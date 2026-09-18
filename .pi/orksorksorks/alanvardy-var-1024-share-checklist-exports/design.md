# Design Discussion — Share checklist exports (iOS)

## Current State

Export is a three-hop, root-owned flow, all in the single iOS+macOS app target:

1. **Settings row → staged action.** The settings sheet's export row stages
   `requestDataAction(.export)` (CheckStitch/ContentView.swift:498), pushed onto
   a FIFO queue by `SettingsViewModel.stage` (:530; pinned by
   `SettingsDataActionQueueTests`).
2. **Sheet dismiss → 400 ms → `perform(.export)`.** `.onChange(of:
   settingsVM.showsSettings)` (:106-116) fires on dismissal, takes the staged
   action, sleeps 400 ms, then calls `perform(action)` → `beginExport()`
   (:538). The sleep is an explicit **macOS-only workaround**: a sheet-nested
   `.fileExporter` never presents its panel (:110-112),
   repeated in ExportChecklistsView.swift:4-5.
3. **Multi-select sheet → document → save panel.** `beginExport()` clears the
   selection and sets `isShowingExport = true`
   (CheckStitch/ChecklistImportExportViewModel.swift:26-30).
   `ExportChecklistsView` toggles `exportSelection`, with `canExport` and the
   pure `toggled(_:id:)` helper exposed for tests (ExportChecklistsView.swift:13-19).
   Its one "Export" button calls `onExport` → `exportSelected()`
   (ChecklistImportExportViewModel.swift:44-53): clears `isShowingExport`,
   filters `store.checklists`, returns early on empty selection, else builds
   `exportDocument = try ChecklistExportDocument(checklists:)` and sets
   `isExporting = true`. `.fileExporter` on the root view presents it
   (`contentType: .json`, `defaultFilename: ChecklistExport.filename()`,
   ContentView.swift:169-177); failure → `exportFailed(error)`.

The payload is entirely in-memory and needs no staging:
`ChecklistExportDocument.data` (`let data: Data`,
CheckStitch/ChecklistExportDocument.swift:11-28); bytes are
`ChecklistCodec.encode(ChecklistEnvelope(version:..., deviceID: "",
checklists: <subset>, tombstones: []))`
(CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift:8-17); filename is
`CheckStitch-YYYY-MM-DD`, **no extension** — `.fileExporter` appends `.json`
from the content type (:21-27). No `URL`, no temp file, no security scope exists
on the export path; the only `startAccessingSecurityScopedResource()` use is the
import read (ChecklistImportExportViewModel.swift:67-80). No share-sheet call
site exists anywhere in the repo (research Q4).

## Desired End State

On **iOS**, the export multi-select sheet offers two actions next to each other:
"Export" (unchanged save panel) and "Share…". Picking Share opens the system
share sheet (Messages, Mail, AirDrop, Save to Files, …) with a
`CheckStitch-YYYY-MM-DD.json` attachment built from the same encoded bytes the
save panel would write. On **macOS** nothing changes — the save panel remains
the only export action.

Verified correct when, on an iOS simulator/device:

- The export sheet shows both actions; both are disabled with an empty
  selection (`canExport` gates both).
- "Export" produces exactly today's save panel and file contents.
- "Share…" presents the system share sheet, and choosing Messages or Mail shows
  a `.json` attachment named `CheckStitch-<date>.json` whose contents decode back
  to the selected checklists through the existing import path.
- `make build` (iOS + macOS slices), `make test-unit` and `./scripts/test.sh`
  all pass with warnings-as-errors.

## Patterns to Follow

- **Root-owned panel presentation.** Every platform panel is anchored to the
  root `ContentView`, never inside a sheet (ContentView.swift:169-177 for
  `.fileExporter`, :176-186 `.fileImporter`, :160-167 the selection sheet).
  The share sheet follows the same ownership rule.
- **VM-driven presentation via `Binding(get:set:)`.** Existing precedent
  ContentView.swift:99-103, :160-162, :169-170 — the view never owns modal
  state; the view model does, and dismissal setters call VM methods
  (`dismissExport()`, `dismissExportSelection()`).
- **Pure, unit-testable helpers on the view.** `ExportChecklistsView.canExport`
  and `static func toggled(_:id:)` (ExportChecklistsView.swift:13-19) exist
  precisely so state logic is testable without a live hierarchy — the new
  share action reuses `canExport` rather than adding inline `!selection.isEmpty`.
- **Compile-time platform gating inside shared files.** `#if os(iOS)` /
  `#if os(macOS)` at ContentView.swift:44, :68, :94, :118; the app target is one
  source set for both platforms (conventions, `SUPPORTED_PLATFORMS`). New files
  under `CheckStitch/` need no `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`).
- **Suites opt into `@MainActor`** in Swift Testing structs; tests deliberately
  do not set `SWIFT_DEFAULT_ACTOR_ISOLATION` (conventions).
- **Handoff on sheet dismissal, not a sleep.** The only sanctioned sequencing
  hook in the codebase for "present after this sheet closes" is the dismissal
  observation (ContentView.swift:106); iOS gives us the stronger hook
  `.sheet(onDismiss:)`, which is what the share handoff should use.

**Patterns NOT to follow:**

- **Do not copy the 400 ms `Task.sleep`.** It is a macOS `fileExporter`-in-sheet
  workaround (ContentView.swift:113-116); the share path is iOS-only, where a
  `.sheet(onDismiss:)` handoff is deterministic. Copying the sleep would add an
  unexplained delay.
- **Do not stage a temp file or wrap the write in security scoping.** The
  `startAccessingSecurityScopedResource()` pair
  (ChecklistImportExportViewModel.swift:67-80) exists to read a *foreign*
  file; we own these bytes and the design deliberately keeps them in memory.
- **Do not put share plumbing in `CheckStitchCore`.** Core never touches
  platform UI; all panel/share plumbing stays in `CheckStitch/` (research
  cross-cutting observations).

## Design Decisions

1. **Share sits beside save, not instead of it (Q1=A):** the sheet gains a
   second action; `.fileExporter`, `isExporting`, `dismissExport()` and their
   tests are untouched. Two actions, no new chooser modal, no regression to a
   tested surface.
2. **iOS only (Q2=B):** the whole share surface is `#if os(iOS)`. macOS keeps
   today's save panel. This removes the ticket's biggest unknown — research Q4
   flags the macOS raw-bytes input path as undocumented and puts
   `NSSharingServicePicker` behind popover/anchoring caveats — and keeps the
   macOS slice byte-for-byte unchanged.
3. **In-memory bytes, no staging (Q3=A + Q4=A), realised imperatively:** the
   shared item is an `NSItemProvider` built with
   `registerDataRepresentation(forTypeIdentifier: UTType.json.identifier)`
   returning the document's existing `Data`, with
   `suggestedName = ChecklistExport.filename() + ".json"`. This is the imperative
   counterpart of SwiftUI's `DataRepresentation` and needs no file URL, no temp
   file and no security scope.
   *Rejected:* `ShareLink(item:)` with a `Transferable`/`DataRepresentation`
   conformance — `ShareLink` is a button that presents its own popover and
   cannot be triggered programmatically from root-owned state (Q4=A), and it
   would drag the unproven macOS path (Q2=B) back in.
   *Rejected:* `FileRepresentation`/temp-file staging (Q3=B) — a file lifecycle
   and cleanup for no gain on iOS.
4. **Root-owned presentation with a dismissal handoff (Q4=A):** `shareSelected()`
   in `ChecklistImportExportViewModel` mirrors `exportSelected()` (clears
   `isShowingExport`, filters the selection, returns on empty, builds the
   document) but records a pending share instead of presenting. The root view's
   export-sheet `onDismiss` promotes pending → presented. This keeps one
   presenter, keeps the state machine unit-testable, and avoids presenting a
   modal while another is mid-dismissal.
5. **Reuse `exportDocument` as the shared payload (Q5=A):** the share carries
   the same `ChecklistExportDocument` bytes — one format, round-trips through
   the existing import path, and `ChecklistExportTests` continue to describe
   what is shared. No second codec, no text rendering.
6. **Pure item construction in an un-gated helper:** a small
   `ChecklistShare.itemProvider(for:filename:)` compiled for both platforms so
   the macOS-hosted unit suite can assert type identifier, `suggestedName` and
   the bytes an `NSItemProvider` yields — the representable itself stays
   `#if os(iOS)` and untested, as SwiftUI/UIKit wrappers always are here.
7. **No error surface for share:** `UIActivityViewController` reports success
   or cancellation via `completionWithItemsHandler`, not an `Error`, so there is
   no `shareErrorMessage` and no alert. Cancelling simply dismisses.

### Shape of the change (indicative, not a specification)

- `CheckStitch/ChecklistShare.swift` (new): `enum ChecklistShare` with the pure
  `itemProvider(...)` builder, plus `#if os(iOS) struct ShareSheet:
  UIViewControllerRepresentable` wrapping `UIActivityViewController` (sets
  `popoverPresentationController.sourceView`/`sourceRect` in
  `updateUIViewController` for iPad).
- `ChecklistImportExportViewModel`: `pendingShare: ChecklistExportDocument?`,
  `private(set) var isSharing`, `shareSelected()`,
  `presentPendingShare()`, `dismissShare()`.
- `ExportChecklistsView`: second closure `onShare: () -> Void` and a "Share…"
  button gated by the same `canExport`.
- `ContentView`: `#if os(iOS)` share `.sheet` on the root view; the export
  sheet's `.sheet(isPresented:onDismiss:)` gains the handoff.

## What We're NOT Doing

- **No macOS share path** (no `NSSharingServicePicker`, no `ShareLink`
  cross-platform wrapper) — Q2=B.
- **Not replacing or removing `.fileExporter`**, and not changing
  `isExporting`/`dismissExport()` semantics.
- **No changes to the export format**: no codec, envelope, version or
  filename-stem change; the `.json` extension is appended for sharing only,
  exactly as `.fileExporter` derives it from `contentType: .json`.
- **No temp-file staging and no security-scoped export plumbing.**
- **No new `INFOPLIST_KEY_*` entries.** Research Q4's
  `LSSupportsOpeningDocumentsInPlace`/`UIFileSharingEnabled` escape hatches are
  only needed if the "Save to Files" bug (FB11766691) is *observed*; adopting
  them speculatively changes both slices' generated Info.plist.
- **No share extension target, no custom `UIActivity`, no custom share UI** —
  system share sheet only.
- **No new share entry points** (no per-row share on the checklist list or
  detail screen); sharing is reachable only from the export multi-select.
- **No UI-test coverage of the share sheet** — it is system UI outside the app
  process; unit tests cover the view model and item construction, and the
  outcome is verified by running on a device/simulator (AGENTS.md: sync/icon
  tickets cannot close on static evidence).
- **No error alert for share** (decision 7).

## Open Risks

1. **Recipient fidelity of an in-memory `NSItemProvider`.** Registering a data
   representation under `UTType.json` with `suggestedName` should reach
   Messages/Mail as a named `.json` attachment and Save-to-Files as a file, but
   the exact per-target behaviour is only proven by running it. Fallback if a
   target drops the name or the attachment: stage the bytes in
   `FileManager.default.temporaryDirectory` and share the file URL — explicitly
   the rejected option 3=B, so this is a contingency, not a planned step.
2. **Presentation timing.** `shareSelected()` is called from inside the export
   sheet, so the share modal must not be requested until that sheet has
   finished dismissing. Mitigated by the `onDismiss` handoff (decision 4); the
   failure signature would be a UIKit "attempt to present … while a
   presentation is in progress" warning and a no-op share sheet.
3. **iPad popover requirement.** `UIActivityViewController` must have a popover
   anchor on iPad or it traps at runtime; the representable sets `sourceView`/
   `sourceRect`, but this is the kind of thing the compiler cannot check and is
   verified by running on an iPad simulator.
4. **Warnings-as-errors.** Any `#if os(macOS)`-dead local, an unused import in
   the un-gated builder, or an unused `completionWithItemsHandler` parameter
   fails the gate (conventions).
5. **`exportDocument` being shared state.** Both actions read
   `exportDocument`; a later refactor that clears it on dismissal could break
   the share. Covered by a unit test that the pending share survives until it
   is presented.