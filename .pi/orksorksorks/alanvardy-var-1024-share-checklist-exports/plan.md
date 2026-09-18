# Implementation Plan

## Overview

On **iOS**, the export multi-select gains a second action, **Share…**, beside
the existing **Export**. Share builds an in-memory `NSItemProvider` from the
same `ChecklistExportDocument` bytes the save panel writes and presents the
system share sheet (`UIActivityViewController`) carrying
`CheckStitch-YYYY-MM-DD.json`. macOS keeps today's save panel unchanged; all
share surface is `#if os(iOS)`. Two vertical slices: Phase 1 is the whole share
capability (walking skeleton), Phase 2 hardens timing/edge/platform parity and
performs the on-device fidelity check that cannot be a static test.

**Rules for the implementer** (from the repo `AGENTS.md` / `conventions.md`):
- The gate is `./scripts/test.sh` → `gate: ok`; fast loop is `make test-unit`.
- Every compiling gate leg uses warnings-as-errors (`WARNINGS_AS_ERRORS`) — an
  unused local/import/closure parameter fails the build.
- New files under `CheckStitch/` need **no** `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`).
- Do not touch `.fileExporter`, `isExporting`, `exportDocument` semantics, the
  codec, or the filename stem. Do not stage temp files. Do not add Info.plist
  keys. No macOS share path.

---

## Phase 1: Walking skeleton — "Share…" an in-memory JSON attachment (iOS)

Deliverable: on iOS, the export sheet shows **Export** and **Share…** side by
side (both gated by `canExport`); Share opens the system share sheet with a
`CheckStitch-<date>.json` whose bytes decode back through
`ChecklistCodec.classify(_:) == .loaded`. macOS compiles the un-gated helper
only and behaves exactly as today.

### Changes

#### 1. `ChecklistShare` — pure item-provider builder + iOS representable

**File**: `CheckStitch/ChecklistShare.swift`
**Action**: create

```swift
import Foundation
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

/// Builds the shared payload. The item-provider builder is intentionally
/// un-gated so the macOS-hosted unit suite can assert the type identifier,
/// `suggestedName` and the bytes an `NSItemProvider` yields; the representable
/// itself is iOS-only, as all platform wrappers here are.
enum ChecklistShare {
    /// The document's existing encoded bytes, registered under `UTType.json`
    /// with the `.json`-suffixed suggested name. No file URL, no staging.
    static func itemProvider(for document: ChecklistExportDocument,
                             filename: String) -> NSItemProvider {
        // Capture only the `Data` (Sendable) — the load handler is @Sendable.
        let payload = document.data
        let provider = NSItemProvider()
        provider.suggestedName = filename
        provider.registerDataRepresentation(forTypeIdentifier: UTType.json.identifier) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }
}

#if os(iOS)
/// Root-owned wrapper over `UIActivityViewController`. Anchors the popover so
/// iPad does not trap at presentation time.
struct ShareSheet: UIViewControllerRepresentable {
    let document: ChecklistExportDocument
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [ChecklistShare.itemProvider(for: document, filename: filename)],
            applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX,
                                        y: controller.view.bounds.midY,
                                        width: 0,
                                        height: 0)
        }
    }
}
#endif
```

Notes:
- `NSItemProvider` lives in Foundation on both iOS and macOS, so the builder is
  cross-platform; `UniformTypeIdentifiers` is available on both.
- `registerDataRepresentation`'s load handler returns `Progress?` → `nil`.
- Do **not** add `import CheckStitchCore` here — only `ChecklistExportDocument`
  (app target) and `Data` are used.

#### 2. View-model share state machine

**File**: `CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: modify

Add stored state next to `exportDocument` / `isExporting`:

```swift
var pendingShare: ChecklistExportDocument?
private(set) var isSharing = false
```

Add methods (place them after `dismissExport()` and near `exportSelected()`):

```swift
func dismissShare() {
    isSharing = false
    pendingShare = nil
}

/// Builds the document for the current selection and records a *pending*
/// share. Mirrors `exportSelected()` but does not present: the root view's
/// export-sheet `onDismiss` promotes pending → presented, so no modal is
/// requested while the export sheet is mid-dismissal. An empty selection
/// shares nothing.
func shareSelected() {
    isShowingExport = false
    let selected = store.checklists.filter { exportSelection.contains($0.id) }
    guard !selected.isEmpty else { return }
    do {
        pendingShare = try ChecklistExportDocument(checklists: selected)
    } catch {
        exportErrorMessage = error.localizedDescription
    }
}

/// Promotes a pending share after the export sheet has finished dismissing.
func presentPendingShare() {
    guard pendingShare != nil else { return }
    isSharing = true
}
```

`pendingShare` is deliberately **not** cleared on export-sheet dismissal
(design Open Risk 5): only `dismissShare()` clears it.

#### 3. Export sheet gains the second action

**File**: `CheckStitch/ExportChecklistsView.swift`
**Action**: modify

Add a closure and a button that reuses the same `canExport` predicate — no
inline `!selection.isEmpty`:

```swift
    let onExport: () -> Void
    let onShare: () -> Void
```

Replace the single trailing `Export` button block with a row carrying both
buttons (keep the existing identifiers and add the new one):

```swift
            HStack {
                Button("Export") { onExport() }
                    .disabled(!canExport)
                    .accessibilityIdentifier("confirmExportButton")
                Button("Share…") { onShare() }
                    .disabled(!canExport)
                    .accessibilityIdentifier("shareChecklistsButton")
            }
            .padding()
```

(The `#if os(iOS)` `.presentationDetents` stays as-is; the file is shared and
the button compiles on both slices.)

#### 4. Root-view presentation wiring

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Inside the existing export `.sheet`, pass both closures and add the dismissal
handoff:

```swift
        .sheet(isPresented: Binding(get: { importExportVM.isShowingExport },
                                    set: { if !$0 { importExportVM.dismissExportSelection() } }),
               onDismiss: { importExportVM.presentPendingShare() }) {
            ExportChecklistsView(
                selection: Binding(get: { importExportVM.exportSelection },
                                   set: { importExportVM.exportSelection = $0 }),
                onExport: { importExportVM.exportSelected() },
                onShare: { importExportVM.shareSelected() })
        }
```

The share sheet itself is iOS-only and anchored to the same root view, next to
`.fileExporter` / `.fileImporter` (root-owned panel precedent). The `.json`
suffix is appended here because `ChecklistExport.filename()` deliberately
returns an extension-less stem:

```swift
        #if os(iOS)
        .sheet(isPresented: Binding(get: { importExportVM.isSharing },
                                    set: { if !$0 { importExportVM.dismissShare() } })) {
            if let pending = importExportVM.pendingShare {
                ShareSheet(document: pending,
                           filename: ChecklistExport.filename() + ".json")
            }
        }
        #endif
```

Do not add a `.sheet` inside `ExportChecklistsView`; the share modal must be
root-owned and requested only from `onDismiss`.

#### 5. New provider tests

**File**: `CheckStitchTests/ChecklistShareTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import CheckStitchCore
import Foundation
import Testing
import UniformTypeIdentifiers

@MainActor
struct ChecklistShareTests {
    private func makeDocument(names: [String]) throws -> ChecklistExportDocument {
        let checklists = names.map { Checklist(name: $0, items: [ChecklistItem(title: "Milk")]) }
        return try ChecklistExportDocument(checklists: checklists)
    }

    @Test
    func itemProviderAdvertisesJSONTypeAndSuggestedName() throws {
        let document = try makeDocument(names: ["Groceries"])
        let filename = ChecklistExport.filename() + ".json"

        let provider = ChecklistShare.itemProvider(for: document, filename: filename)

        #expect(provider.suggestedName == filename)
        #expect(provider.registeredTypeIdentifiers.contains(UTType.json.identifier))
    }

    @Test
    func itemProviderYieldsTheDocumentBytes() async throws {
        let document = try makeDocument(names: ["Groceries", "Packing"])

        let provider = ChecklistShare.itemProvider(for: document, filename: "x.json")
        let data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.coderReadCorrupt))
                }
            }
        }

        guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
            Issue.record("provider bytes did not classify as loaded")
            return
        }
        #expect(envelope.checklists.map(\.name) == ["Groceries", "Packing"])
        #expect(envelope.deviceID == "")
        #expect(envelope.tombstones.isEmpty)
    }

    @Test
    func emptyDocumentStillYieldsValidJSONBytes() async throws {
        let document = try ChecklistExportDocument(checklists: [])
        let provider = ChecklistShare.itemProvider(for: document, filename: "x.json")

        let data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.coderReadCorrupt)) }
            }
        }

        guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
            Issue.record("empty document bytes did not classify as loaded")
            return
        }
        #expect(envelope.checklists.isEmpty)
    }
}
```

Uses the existing `makeIsolatedDefaults()` fixture only where a store is
needed; these tests need no store.

#### 6. View-model share tests

**File**: `CheckStitchTests/ChecklistImportExportViewModelTests.swift`
**Action**: modify

Append to the existing `@MainActor` struct (reuses `makeStore(names:)`):

```swift
    @Test
    func shareFiltersBySelectionAndRecordsPendingShareWithoutPresenting() {
        let store = makeStore(names: ["Groceries", "Packing"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = [store.checklists[0].id]

        viewModel.shareSelected()

        #expect(viewModel.pendingShare != nil)
        #expect(!viewModel.isSharing)
        #expect(!viewModel.isShowingExport)
    }

    @Test
    func emptySelectionSharesNothing() {
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = []

        viewModel.shareSelected()

        #expect(viewModel.pendingShare == nil)
        #expect(!viewModel.isSharing)
    }

    /// Design Open Risk 5: the export sheet's own dismissal must not clear the
    /// pending share before `onDismiss` promotes it.
    @Test
    func pendingShareSurvivesTheExportSheetDismissal() {
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = [store.checklists[0].id]
        viewModel.shareSelected()

        viewModel.dismissExportSelection()   // the sheet's setter path
        viewModel.presentPendingShare()      // the onDismiss handoff

        #expect(viewModel.pendingShare != nil)
        #expect(viewModel.isSharing)
    }

    @Test
    func dismissShareClearsIsSharingAndPendingShare() {
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = [store.checklists[0].id]
        viewModel.shareSelected()
        viewModel.presentPendingShare()

        viewModel.dismissShare()

        #expect(!viewModel.isSharing)
        #expect(viewModel.pendingShare == nil)
    }
```

#### 7. Export-view test call sites

**File**: `CheckStitchTests/ExportChecklistsViewTests.swift`
**Action**: modify

The memberwise initializer now has two closure parameters. A single trailing
closure binds to the **last** closure parameter, so the existing call sites
would leave `onExport` unset and fail to compile. Update both
`ExportChecklistsView(selection: .constant([])) {}` call sites (the `empty` and
`filled` locals in `exportViewRendersAndDerivesCanExportFromSelection`) to:

```swift
        let empty = ExportChecklistsView(selection: .constant([]), onExport: {}, onShare: {})
        let filled = ExportChecklistsView(selection: .constant(Set([checklist.id])),
                                          onExport: {}, onShare: {})
```

No new gated assertion — `canExport` (the shared predicate) is already pinned;
the share button reuses it.

### Verification

#### Automated
- [x] `make test-unit` passes — includes the new `ChecklistShareTests` and the
      four new view-model tests, and the updated `ExportChecklistsViewTests`
      call sites.
- [x] `make build` passes (iOS slice compiles the `ShareSheet` and the new
      `onShare` path) with warnings-as-errors.
- [x] `make build-mac` passes (proves the un-gated builder compiles and the
      `#if os(iOS)` share surface is dead-code-clean on macOS — no
      `#if os(macOS)`-dead local, no unused import/closure parameter).

#### Manual
- [ ] `make run` on this worktree's simulator → open Settings → tap the
      **Export** row → the sheet shows **Export** and **Share…**; with nothing
      selected both are disabled.
- [ ] Select one checklist → tap **Share…** → the system share sheet appears
      (it must not be requested while the export sheet is still on screen).
- [ ] Choose **Messages** (or **Mail**) → the composed attachment is named
      `CheckStitch-<today>.json`.
- [ ] Back out and re-run with **Export** → the save panel still appears and
      writes the same file as before (no regression).

---

## Phase 2: Hardening — timing, edge paths, platform parity, verified fidelity

Deliverable: no new entry point. The share capability is re-entrancy safe, its
sad paths are pinned, both slices stay warning-clean, and the two risks the
compiler cannot check (in-memory provider fidelity to each recipient, iPad
popover) are exercised on real targets.

### Changes

#### 1. Re-entrancy guard on `presentPendingShare()`

**File**: `CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: modify

Replace the Phase 1 guard with one that also refuses to re-present while
`isSharing` is already true (Open Risk 2 — "present while a presentation is in
progress"):

```swift
func presentPendingShare() {
    guard pendingShare != nil, !isSharing else { return }
    isSharing = true
}
```

#### 2. Keep the codec-throw branch symmetric with export

**File**: `CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: modify (comment only)

`shareSelected()`'s `catch` already routes to `exportErrorMessage`, matching
`exportSelected()`. Add a short comment documenting that no new error surface
is introduced (design decision 7 — the share sheet reports cancellation, not an
`Error`):

```swift
    } catch {
        // Same error surface as export: the share itself has no error channel.
        exportErrorMessage = error.localizedDescription
    }
```

No behavior change; do **not** add a `shareErrorMessage` or an alert.

#### 3. Confirm one predicate drives both buttons

**File**: `CheckStitch/ExportChecklistsView.swift`
**Action**: review only

Both `.disabled(!canExport)` modifiers reference the single `canExport`
property; no inline `!selection.isEmpty` may survive in the body. No code change
expected.

#### 4. Hardening tests

**File**: `CheckStitchTests/ChecklistImportExportViewModelTests.swift`
**Action**: modify

```swift
    @Test
    func presentingTwicePresentsOnce() {
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = [store.checklists[0].id]
        viewModel.shareSelected()

        viewModel.presentPendingShare()
        viewModel.presentPendingShare()

        #expect(viewModel.isSharing)
        // A re-entrant guard means the second call is a no-op: state stays
        // exactly what one presentation set, and the pending share is intact.
        #expect(viewModel.pendingShare != nil)
    }

    @Test
    func presentingWithNoPendingShareDoesNothing() {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)

        viewModel.presentPendingShare()

        #expect(!viewModel.isSharing)
    }

    /// Pins the reachable success path's error surface: a successful share
    /// reports no error. (The codec-throw branch is structurally unreachable
    /// for this envelope — see the deviation note below.)
    @Test
    func shareSelectedReportsNoErrorOnSuccess() {
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = [store.checklists[0].id]

        viewModel.shareSelected()

        #expect(viewModel.pendingShare != nil)
        #expect(viewModel.exportErrorMessage == nil)
    }
```

#### 5. Provider fidelity re-check (no code change expected)

**File**: `CheckStitchTests/ChecklistShareTests.swift`
**Action**: review only

Phase 1 already pins the type identifier, `suggestedName` and the yielded
bytes. No additional provider test is added in Phase 2.

### Verification

#### Automated
- [x] `make test-unit` passes — all Phase 1 tests remain green unchanged, plus
      `presentingTwicePresentsOnce`, `presentingWithNoPendingShareDoesNothing`
      and `shareSelectedReportsNoErrorOnSuccess`.
- [ ] `./scripts/test.sh` prints `gate: ok` (all compiling legs with
      warnings-as-errors, shellcheck, watch build, shell tests).

#### Manual (required before close — sync/icon/render tickets cannot close on
static evidence, `AGENTS.md`)
- [ ] iPhone simulator, share to **Messages**: attachment visible and named
      `CheckStitch-<date>.json`.
- [ ] iPhone simulator, share to **Mail**: same named attachment.
- [ ] iPhone simulator, share → **Save to Files**: a file is written; import it
      back through the app's Settings → Import row and confirm the checklists
      round-trip.
- [ ] iPad simulator, tap **Share…**: the sheet opens without the popover trap
      (`SIM=<iPad-udid> make run` if the default device is an iPhone).
- [ ] Record the observed names/outcomes in the completion artifact.
- [ ] **Contingency only if a recipient drops the name/attachment:** stage the
      bytes in `FileManager.default.temporaryDirectory` and share the file URL
      (design Open Risk 1, previously rejected option 3=B). Report before
      adopting — do not silently switch.

---

## Deviations from `structure.md` (flagged)

1. **`ShareSheet(document:filename:)` instead of `ShareSheet(data:filename:)`.**
   `structure.md` pins two things that cannot both hold literally: the
   `ChecklistShare.itemProvider(for: ChecklistExportDocument, filename:)`
   contract and a `ShareSheet` storing only `Data`. The representable takes the
   document (same bytes) so it can call the pinned builder without a second
   `itemProvider(data:)` overload.

2. **`codecFailureLeavesNoPendingShare` is not implementable.**
   `ChecklistExport.data` throws only from `JSONEncoder`, and every field of
   `ChecklistEnvelope`/`Checklist`/`ChecklistItem` (strings, ints, dates, an
   enum, arrays) encodes unconditionally — the throw branch is unreachable
   without adding an injection seam that is **not** in `design.md` (and adding
   one would exceed the plan's scope). The code keeps the symmetric `catch`
   (documented in Phase 2, change 2); the test is replaced by
   `shareSelectedReportsNoErrorOnSuccess`, which pins the reachable error
   surface. If you want the unreachable branch covered, the design must first
   add an injectable document builder to the view model.

3. **`ExportChecklistsViewTests.swift` needed call-site updates** (structure
   only mentioned asserting `canExport` reuse). Adding a second closure makes a
   single trailing closure bind to `onShare`, so the existing
   `ExportChecklistsView(selection: .constant(...)) {}` calls must name both
   closures explicitly or they will not compile.