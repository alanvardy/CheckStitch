# Structure Outline

## Approach

Add a second action to the existing iOS export multi-select: "Share…" builds
an in-memory `NSItemProvider` from the same `ChecklistExportDocument` bytes the
save panel writes, and a root-owned `ShareSheet`
(`UIViewControllerRepresentable` over `UIActivityViewController`) presents it.
`shareSelected()` mirrors `exportSelected()` but records a *pending* share; the
export sheet's `onDismiss` promotes it, so no modal is presented mid-dismissal.
macOS keeps today's save panel unchanged (all share surface is `#if os(iOS)`).
Two vertical slices: the walking skeleton is the whole share capability, then a
hardening slice for timing/edge/platform parity plus the on-device fidelity
check that cannot be a static test.

---

## Phase 1: Walking skeleton — "Share…" an in-memory JSON attachment (iOS)

On iOS the export multi-select shows **Export** and **Share…** side by side,
both gated by the existing `canExport`. Selecting checklists and tapping
Share… opens the system share sheet carrying `CheckStitch-YYYY-MM-DD.json`
whose bytes decode back to the selection via the existing import path. macOS
compiles and behaves exactly as today. Green tests prove the item provider's
type identifier / `suggestedName` / bytes, and the view-model state machine;
the sheet itself is proven by running.

**Files**: `CheckStitch/ChecklistShare.swift` (new),
`CheckStitch/ChecklistImportExportViewModel.swift`,
`CheckStitch/ExportChecklistsView.swift`, `CheckStitch/ContentView.swift`,
`CheckStitchTests/ChecklistShareTests.swift` (new),
`CheckStitchTests/ChecklistImportExportViewModelTests.swift`,
`CheckStitchTests/ExportChecklistsViewTests.swift`

**Key changes**:
- `enum ChecklistShare { static func itemProvider(for document: ChecklistExportDocument, filename: String) -> NSItemProvider }` — new, **un-gated** (compiles on both slices), uses `registerDataRepresentation(forTypeIdentifier: UTType.json.identifier)` returning `document.data` and sets `suggestedName = filename`.
- `#if os(iOS) struct ShareSheet: UIViewControllerRepresentable { let data: Data; let filename: String }` — new; `makeUIViewController` builds `UIActivityViewController(activityItems: [itemProvider], applicationActivities: nil)`, `updateUIViewController` sets `popoverPresentationController?.sourceView` / `sourceRect` (iPad trap guard).
- `ChecklistImportExportViewModel.pendingShare: ChecklistExportDocument?` — new; no clear on sheet dismissal.
- `ChecklistImportExportViewModel.isSharing: Bool` (`private(set)`) — new.
- `func shareSelected()` — new; mirrors `exportSelected()`: `isShowingExport = false`, filter `store.checklists` by `exportSelection`, return on empty, else `pendingShare = try ChecklistExportDocument(checklists: selected)` (on throw reuse `exportErrorMessage`, as export does).
- `func presentPendingShare()` — new; `guard pendingShare != nil`, then `isSharing = true`.
- `func dismissShare()` — new; `isSharing = false; pendingShare = nil`.
- `ExportChecklistsView.onShare: () -> Void` — new second closure; add `Button("Share…") { onShare() }.disabled(!canExport).accessibilityIdentifier("shareChecklistsButton")` next to Export.
- `ContentView`: export `.sheet(..., onDismiss: { importExportVM.presentPendingShare() })` + pass `onShare: { importExportVM.shareSelected() }`; add `#if os(iOS)` share `.sheet(isPresented: Binding(get: { importExportVM.isSharing }, set: { if !$0 { importExportVM.dismissShare() } }))` rendering `ShareSheet(data:filename:)` from `pendingShare`.

**Contract** (what Phase 2 and any follow-on may depend on):
`ChecklistShare.itemProvider(for:filename:) -> NSItemProvider` (un-gated);
iOS `ShareSheet(data:filename:)`; VM surface `pendingShare`, `isSharing`,
`shareSelected()`, `presentPendingShare()`, `dismissShare()`;
`ExportChecklistsView(selection:onExport:onShare:)`. `.fileExporter`,
`isExporting`, `dismissExport()` are untouched.

**Tests**:
- `ChecklistShareTests` (new, Swift Testing, async): `itemProviderAdvertisesJSONTypeAndSuggestedName` (representation exists for `UTType.json.identifier`; `suggestedName == "CheckStitch-<date>.json"`), `itemProviderYieldsTheDocumentBytes` (loaded `Data` decodes `.loaded` to the same checklists) — happy path + the empty document (`#expect` still yields valid empty-JSON bytes).
- `ChecklistImportExportViewModelTests` additions: `shareFiltersBySelectionAndRecordsPendingShareWithoutPresenting` (`pendingShare != nil`, `isSharing == false`, `isShowingExport == false`), `emptySelectionSharesNothing` (sad path), `pendingShareSurvivesTheExportSheetDismissal` (risk 5), `dismissShareClearsIsSharingAndPendingShare`.
- `ExportChecklistsViewTests`: assert the share action reuses `canExport` (same value drives both buttons) — no new gated assertion.

**Verify**: `make test-unit` (unit leg + item-provider assertions) then `make build` (iOS slice) and `make build-mac` (proves the `#if os(iOS)` share surface is dead-code-clean on macOS) both pass with warnings-as-errors. Manual: `make run` on this worktree's simulator → Settings → Export → select a checklist → **Share…** → share to Messages/Mail and confirm a `CheckStitch-<date>.json` attachment; **Export** still opens the save panel.

---

## Phase 2: Hardening — timing, edge paths, platform parity, verified fidelity

No new entry point; it makes the Phase 1 capability robust and *verified*:
re-entrant/double-present is guarded, the codec-failure and no-document sad
paths are pinned by tests, both platform slices stay warning-clean, and the
two risks the compiler cannot check (recipient fidelity of an in-memory
provider, iPad popover) are exercised on real targets.

**Files**: `CheckStitch/ChecklistImportExportViewModel.swift`,
`CheckStitch/ContentView.swift`, `CheckStitch/ChecklistShare.swift`,
`CheckStitchTests/ChecklistImportExportViewModelTests.swift`,
`CheckStitchTests/ChecklistShareTests.swift`

**Key changes**:
- `presentPendingShare()` gains a re-entrancy guard (no-op when `isSharing` is already true or `pendingShare == nil`) — closes the "present while a presentation is in progress" risk (Open Risk 2).
- `shareSelected()` documents/keeps the codec-throw branch symmetrical with `exportSelected()`; add nothing new to the error surface (design decision 7 — cancellation is not an error).
- Confirm both button paths share one predicate, so no inline `!selection.isEmpty` survives.

**Contract**: unchanged from Phase 1 — hardening does not alter the VM/`ChecklistShare` signatures.

**Tests**:
- `ChecklistImportExportViewModelTests`: `presentingTwicePresentsOnce` (call `presentPendingShare()` twice → `isSharing` stays true, no double presentation state), `presentingWithNoPendingShareDoesNothing` (sad path), `codecFailureLeavesNoPendingShare` (sad path).
- Existing Phase 1 tests remain green unchanged.

**Verify**: `make test-unit` passes; then the full gate `./scripts/test.sh` prints `gate: ok` (warnings-as-errors on every compiling leg, shellcheck). Manual, required before close (sync/icon/render tickets cannot close on static evidence, AGENTS.md):
- iPhone simulator: share to **Messages** and **Mail** shows `CheckStitch-<date>.json`; **Save to Files** writes a file; re-import proves the round-trip.
- iPad simulator: share opens without the popover trap.
If a target drops the name/attachment, the contingency is temp-file staging (design Open Risk 1) — report before adopting, do not silently switch.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` + `make build` + `make build-mac` green (provider type/name/bytes; VM pending→present→dismiss; empty selection shares nothing; macOS slice compiles with share surface gated out).
- After Phase 2: **all Phase 1 tests still green**, re-entrancy/empty-codec sad paths green, `./scripts/test.sh` → `gate: ok`, and the iPhone/iPad manual fidelity checks recorded in the completion artifact.
- If a checkpoint fails, stop — do not start the next slice.