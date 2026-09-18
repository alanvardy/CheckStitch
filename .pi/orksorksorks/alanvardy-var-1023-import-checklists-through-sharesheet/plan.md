# Implementation Plan

Ticket: VAR-1023 — import checklists through the Share Sheet / Open In.
All work lands on this one ticket/PR. Every phase below is a vertical slice:
config + seam + behaviour + tests, not a layer.

## Overview

Register `public.json` as a document type so iOS/macOS hand shared CheckStitch
files to the app; funnel every OS delivery through one idempotent
`SharedImportInbox`; split the import session into `stage` → selection → `commit`
so only the ticked checklists reach the `ChecklistStore`, with the existing FIFO
conflict dialog for ticked conflicts only.

Baseline facts used throughout (from `conventions.md`, no re-read required):
- New Swift files under `CheckStitch/` need **no** `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`).
- Gate = `bash scripts/test.sh` (prints `gate: ok`); fast loop = `make test-unit`.
- Compiling legs enforce warnings-as-errors, so `make build` / `make test-unit`
  are the API oracle.
- App target carries `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; test targets
  do **not** — new test suites opt in with `@MainActor`.
- Swift Testing (`struct`, `@Test`, `#expect`) for session/VM/inbox suites.

Source anchors referenced below (already summarized in `research.md`):
`CheckStitch/ChecklistImportSession.swift`, `CheckStitch/ChecklistImportExportViewModel.swift`,
`CheckStitch/ExportChecklistsView.swift`, `CheckStitch/ContentView.swift`,
`CheckStitch/AppDelegate.swift`, `CheckStitch/ChecklistStore.swift` (`importInsert`,
`importReplace`, `conflictingChecklist(named:)`), `CheckStitch.xcodeproj/project.pbxproj`
(app-target `Debug` = `000000000000000111000000`, `Release` = `000000000000000112000000`).

---

## Phase 1: Walking skeleton — an OS share / Open-In reaches the store

A CheckStitch JSON opened from Mail/Files via "Open In" launches CheckStitch and
its checklists are imported (all of them — current `prepare` semantics, no
selection yet). Green tests prove the OS hands us the URL exactly once and the
store gains the file's checklists. The plist/pbxproj wiring is the only
horizontal config in this plan; it cannot demo alone and rides with the
reception skeleton.

### Changes

#### 1. Source Info.plist (new)
**File**: `CheckStitch/Info.plist`
**Action**: create

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>CheckStitch Checklist</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.json</string>
			</array>
		</dict>
	</array>
	<key>LSSupportsOpeningDocumentsInPlace</key>
	<true/>
</dict>
</plist>
```

`GENERATE_INFOPLIST_FILE = YES` stays on; the file is the base and generated keys
(`NSReminders*UsageDescription`, scene manifest, orientations) merge over it.

#### 2. App-target build settings
**File**: `CheckStitch.xcodeproj/project.pbxproj`
**Action**: modify

Add exactly one line to each of the two app-target `XCBuildConfiguration` blocks
(`000000000000000111000000` Debug, `000000000000000112000000` Release), beside
`GENERATE_INFOPLIST_FILE = YES;`:

```
				INFOPLIST_FILE = CheckStitch/Info.plist;
```

Do **not** touch the watch target configs (lines 683/712) or test-target configs.

#### 3. `SharedImportFile` + `SharedImportInbox` (new)
**File**: `CheckStitch/SharedImportInbox.swift`
**Action**: create

```swift
import Foundation
import Observation

/// A file handed to CheckStitch by the OS (Open In / share / document open).
struct SharedImportFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let displayName: String
}

/// The single funnel for every OS file delivery. Scene delivery (`onOpenURL`)
/// and app-delegate delivery (`application(_:open:)`) both call `receive(url:)`;
/// a cold-start arrival is held in `pending` until the root view consumes it.
///
/// Idempotent per URL: the same URL delivered twice (both hooks firing, or a
/// re-delivery) neither replaces nor duplicates the pending file.
@MainActor
@Observable
final class SharedImportInbox {
    static let shared = SharedImportInbox()

    private(set) var pending: SharedImportFile?
    private var lastReceivedURL: URL?

    private init() {}

    func receive(url: URL) {
        guard url != lastReceivedURL else { return }
        lastReceivedURL = url
        pending = SharedImportFile(id: UUID(), url: url, displayName: url.lastPathComponent)
    }

    /// Returns the pending file once and clears it.
    func consume() -> SharedImportFile? {
        defer { pending = nil }
        return pending
    }
}
```

Note: `lastReceivedURL` is deliberately kept across `consume()` so a double-fire
cannot re-open the sheet; a *distinct* URL always replaces (Phase 3).

#### 4. App-delegate open handlers
**File**: `CheckStitch/AppDelegate.swift`
**Action**: modify

Inside the `#if os(iOS)` `AppDelegate` class body, add:

```swift
        func application(
            _: UIApplication,
            open url: URL,
            options _: [UIApplication.OpenURLOptionsKey: Any] = [:]
        ) -> Bool {
            SharedImportInbox.shared.receive(url: url)
            return true
        }
```

Inside the `#if os(macOS)` `MacAppDelegate` class body, add:

```swift
        func application(_: NSApplication, open urls: [URL]) {
            for url in urls { SharedImportInbox.shared.receive(url: url) }
        }
```

Both classes are implicitly `@MainActor` (app-target default isolation), so the
direct call compiles. Compiler is the oracle here.

#### 5. Root view consumes the arrival
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add two modifiers to the root `.modifier(TextSizeModifier(textSize: textSize))`
chain (next to the existing `.task { await backgroundVM.task(...) }`), plus the
private helper:

```swift
        .onOpenURL { url in
            SharedImportInbox.shared.receive(url: url)
            consumePendingSharedImport()
        }
        .task {
            // A cold-start arrival must reach the same consume path once the
            // root exists.
            consumePendingSharedImport()
        }
```

```swift
    private func consumePendingSharedImport() {
        guard let file = SharedImportInbox.shared.consume() else { return }
        importExportVM.importFile(at: file.url)
    }
```

`.onOpenURL` is the primary scene-based hook; the delegate hook covers the case
SwiftUI does not surface. Both meet in `receive(url:)`.

#### 6. View model
**File**: `CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: no functional change this phase

`importFile(at:)` already wraps the read in
`startAccessingSecurityScopedResource` / `defer stop…` and calls
`session.prepare(data:)`. Phase 1 relies on that path unchanged. (Phase 2 edits
this file.)

#### 7. New `SharedImportInboxTests`
**File**: `CheckStitchTests/SharedImportInboxTests.swift`
**Action**: create

```swift
@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct SharedImportInboxTests {
    @Test
    func receivesSameURLOnce() {
        let inbox = SharedImportInbox.shared
        _ = inbox.consume()                       // isolate from other suites
        let url = URL(fileURLWithPath: "/tmp/a.json")

        inbox.receive(url: url)
        inbox.receive(url: url)

        #expect(inbox.pending?.url == url)
        #expect(inbox.consume()?.url == url)
        #expect(inbox.consume() == nil, "one arrival consumes exactly once")
    }

    @Test
    func coldStartArrivalConsumesOnce() {
        let inbox = SharedImportInbox.shared
        _ = inbox.consume()
        let url = URL(fileURLWithPath: "/tmp/cold.json")

        inbox.receive(url: url)                   // delegated before root exists
        #expect(inbox.pending != nil, "arrival survives until the root consumes")

        #expect(inbox.consume()?.displayName == "cold.json")
        #expect(inbox.pending == nil)
        #expect(inbox.consume() == nil)
    }
}
```

`consume()` first is the test-isolation dance for the shared singleton. If the
singleton proves awkward across suites, keep it (design decision 2) and reset
via `consume()` at the top of every inbox test.

#### 8. Shell assertion
**File**: `scripts/tests/run.sh`
**Action**: modify

Add a phase-1 case (function + `run_case` registration near the other
`run_case` calls), mode `100755` preserved:

```bash
# --- document-type registration --------------------------------------------

documentTypeRegistrationWiresInfoPlist() {
    grep -q "CFBundleDocumentTypes" CheckStitch/Info.plist || return 1
    grep -q "public.json" CheckStitch/Info.plist || return 1
    # Both app-target configurations (Debug + Release) must set INFOPLIST_FILE.
    local count
    count="$(grep -c "INFOPLIST_FILE = CheckStitch/Info.plist;" \
        CheckStitch.xcodeproj/project.pbxproj)"
    [[ "$count" -eq 2 ]]
}

run_case documentTypeRegistrationWiresInfoPlist documentTypeRegistrationWiresInfoPlist
```

#### 9. Existing tests untouched
`ChecklistImportSessionTests` / `ChecklistImportExportViewModelTests` still
exercise `prepare(data:)` and stay green this phase; they are rewritten in
Phase 2. `ChecklistImportExportViewModelTests.importFileReadsAndCommitsAll`
still passes because `importFile(at:)` is unchanged.

### Verification
#### Automated
- [x] `make build` passes (warnings-as-errors; proves the plist merge and both
      delegate signatures compile on iOS + macOS)
- [x] `make test-unit` passes, including the new `SharedImportInboxTests`
- [x] `bash scripts/tests/run.sh` prints `tests: N passed, 0 failed`
      (`documentTypeRegistrationWiresInfoPlist` green)
- [x] Built plist carries the doc type:
      `bash -c 'plutil -p "$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/CheckStitch.app/Info.plist" | head -1)" | grep -A3 CFBundleDocumentTypes'`
      shows `public.json`
- [x] `plutil -p <same Info.plist> | grep -q NSRemindersUsageDescription` —
      generated keys still merged over the source file

#### Manual
- [ ] `make run`; the app launches normally (plist regression check)
- [ ] Put a CheckStitch JSON in Files → tap → "Open In / Share → CheckStitch" →
      the app foregrounds and the file's checklists appear in the list (all of
      them this phase)
- [ ] Open the same file twice in a row from Files — the second open does not
      double-import (idempotent inbox)

**Fallback if the `INFOPLIST_FILE` + `GENERATE_INFOPLIST_FILE` merge fails**
(design open risk 1): keep `GENERATE_INFOPLIST_FILE = YES`, express the scalar
key as `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES` and move
`CFBundleDocumentTypes` back in via a generated-file post-process in the Makefile
`build` recipe. The shell assertion in step 8 then checks the *built* plist
instead of the source file. This is an implementation fallback, not a design
change.

---

## Phase 2: Selection — only the ticked checklists are imported

Any arrival (share **or** in-app picker) shows a checkmark sheet listing the
file's checklists, all ticked; Confirm imports exactly the ticked ones; Cancel
leaves the store untouched. Conflicts are raised only for ticked checklists.

### Changes

#### 1. Stage/commit split
**File**: `CheckStitch/ChecklistImportSession.swift`
**Action**: modify

Replace `prepare(data:)` with `stage(data:)` + `commit(selectedIDs:)`, add
`discard()`, keep `decide(_:for:)`/`pending`/`summary` semantics, and change
`ChecklistImportCandidate.id` to the file's checklist UUID.

```swift
/// One decoded checklist presented to the import flow. `id` is the FILE's
/// checklist id (stable across stage/commit and with the selection set);
/// `conflicting` is the local checklist it collides with, or `nil`.
struct ChecklistImportCandidate: Identifiable, Equatable {
    let id: UUID
    let checklist: Checklist
    let conflicting: Checklist?
}
```

```swift
    private(set) var candidates: [ChecklistImportCandidate] = []
    private(set) var pending: [ChecklistImportCandidate] = []
    private(set) var summary = ImportSummary()

    /// Decodes `data` and exposes the file's checklists for selection WITHOUT
    /// touching the store (only the read-only `conflictingChecklist` is called).
    /// Throws for a payload this build cannot read or understand, before any
    /// staging. Prior candidates/pending/summary are reset at entry.
    @discardableResult
    func stage(data: Data) throws -> [ChecklistImportCandidate] {
        pending = []
        summary = ImportSummary()
        candidates = []
        let incoming = try decoded(data)
        candidates = incoming.map { checklist in
            ChecklistImportCandidate(
                id: checklist.id,
                checklist: checklist,
                conflicting: store.conflictingChecklist(named: checklist.name))
        }
        return candidates
    }

    /// Imports exactly `selectedIDs`, in file order. The conflict check is
    /// re-run here (authoritative): a selected name that now collides is left
    /// `pending` for a FIFO decision; unselected names are never enqueued.
    @discardableResult
    func commit(selectedIDs: Set<UUID>) -> ImportSummary {
        var result = ImportSummary()
        for candidate in candidates where selectedIDs.contains(candidate.id) {
            if let conflict = store.conflictingChecklist(named: candidate.checklist.name) {
                pending.append(ChecklistImportCandidate(
                    id: candidate.id, checklist: candidate.checklist, conflicting: conflict))
            } else {
                store.importInsert(candidate.checklist)
                result.inserted += 1
            }
        }
        summary = result
        return result
    }

    /// Drops a staged file (Cancel / swipe-away). No store writes either way.
    func discard() {
        candidates = []
        pending = []
        summary = ImportSummary()
    }

    /// The decode+migrate half of the old `prepare`.
    private func decoded(_ data: Data) throws -> [Checklist] {
        switch ChecklistCodec.classify(data) {
        case .loaded(let envelope):
            return envelope.checklists
        case .migratable(let from, let envelope):
            return envelope.checklists.map { checklist in
                switch from {
                case 1: return checklist.migrated(at: now())
                case 2: return checklist.seededOrder()
                default: return checklist
                }
            }
        case .unsupportedVersion:
            throw ChecklistImportError.unsupportedVersion
        case .unreadable:
            throw ChecklistImportError.unreadable
        }
    }
```

`decide(_:for:)` is unchanged (still `pending.remove` + `importReplace` /
`importInsert` / no-op, incrementing `summary`).

#### 2. Generic selection sheet (new)
**File**: `CheckStitch/ChecklistSelectionView.swift`
**Action**: create

```swift
import Foundation
import SwiftUI

/// One selectable row: a checklist identity, its display name, optional caption.
struct ChecklistSelectionRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detail: String?
}

/// Shared checkmark multi-select sheet for export and import. Pure selection
/// helpers (`toggled`, `canConfirm`) are exposed for tests.
struct ChecklistSelectionView: View {
    let title: String
    let rows: [ChecklistSelectionRow]
    @Binding var selection: Set<UUID>
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let rowAccessibilityID: String
    let confirmAccessibilityID: String

    /// Pure, so the disable state is unit-testable without a live hierarchy.
    var canConfirm: Bool { !selection.isEmpty }

    /// Pure toggle helper, exposed for tests.
    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        var next = selection
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
            }
            .padding()
            Text("Select the checklists to include.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            List(rows) { row in
                Button {
                    selection = Self.toggled(selection, id: row.id)
                } label: {
                    HStack {
                        Image(systemName: selection.contains(row.id)
                              ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            if let detail = row.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(rowAccessibilityID)
            }
            Button(confirmTitle) { onConfirm() }
                .disabled(!canConfirm)
                .accessibilityIdentifier(confirmAccessibilityID)
                .padding()
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
```

#### 3. Export sheet refactored onto it
**File**: `CheckStitch/ExportChecklistsView.swift`
**Action**: modify

```swift
struct ExportChecklistsView: View {
    @Environment(ChecklistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<UUID>
    let onExport: () -> Void

    var canExport: Bool { !selection.isEmpty }

    /// Kept as a forwarding shim so `ExportChecklistsViewTests` is unchanged.
    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        ChecklistSelectionView.toggled(selection, id: id)
    }

    var body: some View {
        ChecklistSelectionView(
            title: "Export Checklists",
            rows: store.checklists.map {
                ChecklistSelectionRow(id: $0.id, name: $0.name, detail: nil)
            },
            selection: $selection,
            confirmTitle: "Export",
            onConfirm: onExport,
            onCancel: { dismiss() },
            rowAccessibilityID: "exportSelectionRow",
            confirmAccessibilityID: "confirmExportButton")
    }
}
```

Keeping `ExportChecklistsView.toggled` means `ExportChecklistsViewTests`
(`toggledAddsAndRemovesSelection`, `exportViewRendersAndDerivesCanExportFromSelection`)
needs no edit and the export accessibility ids are preserved.

#### 4. View-model selection state
**File**: `CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: modify

Add presentation state and stage/commit/cancel entry points:

```swift
    var importCandidates: [ChecklistImportCandidate] = []
    var importSelection: Set<UUID> = []
    var isShowingImportSelection = false
```

```swift
    /// Reads the file under a security-scoped access/stop pair, stages it (no
    /// store writes), and opens the selection sheet with every row ticked.
    /// A read/format failure reports through `importErrorMessage` and shows no
    /// sheet.
    func importFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            importErrorMessage = error.localizedDescription
            return
        }

        let session = ChecklistImportSession(store: store)
        do {
            importCandidates = try session.stage(data: data)
        } catch let error as ChecklistImportError {
            importErrorMessage = error.message
            return
        } catch {
            importErrorMessage = "This file isn't a CheckStitch export."
            return
        }
        importSession = session
        importSelection = Set(importCandidates.map(\.id))   // all ticked by default
        isShowingImportSelection = true
    }

    /// Commits the ticked checklists, then presents the first selected conflict.
    func commitImport() {
        guard let session = importSession else { return }
        isShowingImportSelection = false
        session.commit(selectedIDs: importSelection)
        conflict = session.pending.first
    }

    /// Cancel / swipe-away: drop the staged file, leave the store untouched.
    func cancelImport() {
        guard isShowingImportSelection else { return }
        isShowingImportSelection = false
        importSession?.discard()
        importSession = nil
        importCandidates = []
        importSelection = []
    }

    func clearImportSelection() {
        importSession?.discard()
        importSession = nil
        importCandidates = []
        importSelection = []
        isShowingImportSelection = false
    }
```

The `guard isShowingImportSelection` in `cancelImport()` makes it a no-op after
`commitImport()` has already set the flag false from the sheet's binding setter
(SwiftUI calls the setter only on user-initiated dismissal).

#### 5. Root presentation
**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Present the selection sheet from the root, beside the export sheet — never from
inside `SettingsView`'s sheet (macOS `.fileImporter`/panel flakiness). Insert
before the existing `.fileExporter` modifier:

```swift
        .sheet(isPresented: Binding(get: { importExportVM.isShowingImportSelection },
                                    set: { if !$0 { importExportVM.cancelImport() } })) {
            ChecklistSelectionView(
                title: "Import Checklists",
                rows: importExportVM.importCandidates.map {
                    ChecklistSelectionRow(
                        id: $0.id,
                        name: $0.checklist.name,
                        detail: $0.conflicting == nil ? nil : "A checklist with this name exists")
                },
                selection: Binding(get: { importExportVM.importSelection },
                                   set: { importExportVM.importSelection = $0 }),
                confirmTitle: "Import",
                onConfirm: { importExportVM.commitImport() },
                onCancel: { importExportVM.cancelImport() },
                rowAccessibilityID: "importSelectionRow",
                confirmAccessibilityID: "confirmImportButton")
        }
```

The existing `.confirmationDialog("Name conflict")` block is unchanged and now
only receives the ticked conflicts.

#### 6. Session suite rewrite
**File**: `CheckStitchTests/ChecklistImportSessionTests.swift`
**Action**: modify

Keep `makeSession()` / `payload(...)` fixtures. Replace the `prepare`-based
assertions with the stage/commit names below (all `@Test`, `@MainActor` struct):

- `stagingWritesNothingToStore` — stage a payload, `#expect(store.checklists.isEmpty)`,
  `tombstones.isEmpty`, `session.pending.isEmpty`, `session.summary == ImportSummary()`,
  and `candidates.count == n` with `candidates.first?.conflicting == nil`.
- `commitImportsOnlySelected` — stage `["A","B"]`, commit `[B.id]`; `store.checklists.map(\.name) == ["B"]`,
  `session.summary.inserted == 1`, `pending.isEmpty`.
- `commitSkipsUnselectedConflicts` — local "Groceries"; stage `[groceries, A]`; commit `[A.id]`;
  `store.checklists` still only the local one, `session.pending.isEmpty`
  ("an unticked conflict is never enqueued").
- `commitEnqueuesSelectedConflictsInFileOrder` — local "Groceries"; stage
  `[Groceries, A, groceries]`; commit all ids; `pending.map(\.checklist.name) == ["Groceries", "groceries"]`
  (file order, second is the case-variant) and `summary.inserted == 1` (A).
- `discardLeavesStoreUnchanged` — stage, `discard()`, `candidates/pending` empty,
  store unchanged.
- `unsupportedVersionThrowsBeforeStaging` — version `currentVersion + 1`,
  `#expect(throws: ChecklistImportError.unsupportedVersion)`, store untouched,
  `candidates.isEmpty`.
- `unreadableThrowsBeforeStaging` — `Data("not json".utf8)`, `.unreadable`, store untouched.
- `migratableStagesNormalisedCandidates` — version 1 then version 2 payloads stage
  and commit, names `["V1"]` / `["V2"]`, `summary.inserted == 1` each.
- `reImportStability` — stage+commit a payload; stage it again; all names now
  conflict; commit → `pending.count == n`; decide `.keepExisting` for each;
  store count unchanged, no tombstone.
- `priorityPreserved` — an item with `.high` survives stage→commit with
  `store.checklists.first?.items.first?.priority == .high`.

The three `decide` tests (`replaceTombstonesAndSwaps`, `keepBothDisambiguates`,
`keepExistingLeavesLocal`) become: `stage` → `commit(selectedIDs: all ids)` →
`session.pending.first` is the candidate → `decide(...)`, same assertions as today
except `candidateID` now comes from `pending.first?.id`.

#### 7. VM suite rewrite
**File**: `CheckStitchTests/ChecklistImportExportViewModelTests.swift`
**Action**: modify

Keep `makeStore(names:)` / `writeTempFile(_:)` fixtures. Existing export tests
unchanged. Replace/add:

- `importFileStagesAndPresentsSelection` — `importFile(at:)` a temp export;
  `#expect(viewModel.isShowingImportSelection)`, `importCandidates.map(\.checklist.name)`
  matches the file, `importSelection == Set(importCandidates.map(\.id))`, and
  `store.checklists.isEmpty` (nothing written yet).
- `commitImportAppliesTickSelection` — stage a two-checklist file, remove one id
  from `importSelection`, `commitImport()`; store has only the ticked name,
  `isShowingImportSelection == false`.
- `cancelImportDiscardsStagedFile` — stage then `cancelImport()`; store
  unchanged, `importCandidates.isEmpty`, `importSelection.isEmpty`, no sheet.
- `emptySelectionCannotConfirm` — pure view check:
  `ChecklistSelectionView(title:"t", rows:[], selection: .constant([]), confirmTitle:"Import",
  onConfirm:{}, onCancel:{}, rowAccessibilityID:"r", confirmAccessibilityID:"c").canConfirm == false`,
  and a one-id selection → `true`.
- `conflictDecisionsAdvanceTheFIFOQueue` — the existing test, with a
  `viewModel.commitImport()` inserted after `importFile(at:)` and before reading
  `viewModel.conflict`, so the queue is populated. `await Task.yield()` machinery
  stays.
- Read/format failure tests (`importFileReportsReadFailure` /
  `importFileReportsFormatFailure`) keep asserting `importErrorMessage`, and gain
  `#expect(!viewModel.isShowingImportSelection)`.

### Verification
#### Automated
- [x] `make test-unit` passes (session + VM + inbox + export suites)
- [x] `make build` passes (new `ChecklistSelectionView` API type-checks against
      the iOS + macOS SDKs)
- [x] `bash scripts/tests/run.sh` still prints `tests: N passed, 0 failed`

#### Manual
- [ ] `make run` → in-app "Import" from Settings shows the checkmark sheet with
      all rows ticked; untick one, Import → only the ticked checklist appears
- [ ] Repeat and press Cancel (and separately swipe the sheet down) → the list
      is unchanged
- [ ] Import a file whose only checklist name already exists, untick it, Import
      → **no** conflict dialog and the list is unchanged
- [ ] Import with a conflicting name ticked → the existing Replace / Keep Both /
      Keep Existing dialog appears once per ticked conflict

---

## Phase 3: Robustness — bad and repeated arrivals never touch the store

A non-CheckStitch or newer-version JSON shows the existing "Couldn't import"
alert with **no** sheet; a second share replaces the pending file; a cold-start
arrival is consumed exactly once; cancel leaves the store byte-identical.

### Changes

#### 1. Replace-on-second-arrival + reset stale conflict
**File**: `CheckStitch/ChecklistImportExportViewModel.swift`
**Action**: modify

At the top of `importFile(at:)`, before reading, clear any in-flight conflict
from a previous arrival so "last arrival wins":

```swift
    func importFile(at url: URL) {
        conflict = nil
        let accessing = url.startAccessingSecurityScopedResource()
        ...
```

`importFile` already replaces `importSession`, `importCandidates`,
`importSelection` and re-shows the sheet, so a distinct URL received while the
sheet is open re-stages over the old file. No change to `receive(url:)` is
needed for replacement — `receive` always replaces `pending` for a distinct URL
(Phase 1).

#### 2. Pending consumed from the root
**File**: `CheckStitch/ContentView.swift`
**Action**: no further change

Phase 1's `.onOpenURL { receive; consumePendingSharedImport() }` + `.task {
consumePendingSharedImport() }` already route a pre-root arrival to the sheet
exactly once (`consume()` clears `pending`). Confirm in step 3's test that a
cold-start arrival is consumed exactly once.

#### 3. Inbox tests
**File**: `CheckStitchTests/SharedImportInboxTests.swift`
**Action**: modify

Add:

```swift
    @Test
    func secondDistinctArrivalReplacesPending() {
        let inbox = SharedImportInbox.shared
        _ = inbox.consume()
        let first = URL(fileURLWithPath: "/tmp/first.json")
        let second = URL(fileURLWithPath: "/tmp/second.json")

        inbox.receive(url: first)
        inbox.receive(url: second)

        #expect(inbox.consume()?.url == second)
        #expect(inbox.consume() == nil)
    }
```

#### 4. VM sad-path tests
**File**: `CheckStitchTests/ChecklistImportExportViewModelTests.swift`
**Action**: modify

Add:

```swift
    @Test
    func unreadableFileShowsAlertAndNoSheet() throws {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let url = try writeTempFile(Data("not json".utf8))

        viewModel.importFile(at: url)

        #expect(viewModel.importErrorMessage != nil)
        #expect(!viewModel.isShowingImportSelection)
        #expect(store.checklists.isEmpty)
    }

    @Test
    func unsupportedVersionShowsAlertAndNoSheet() throws {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let envelope = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion + 1, deviceID: "", checklists: [])
        let url = try writeTempFile(try ChecklistCodec.encode(envelope))

        viewModel.importFile(at: url)

        #expect(viewModel.importErrorMessage != nil)
        #expect(!viewModel.isShowingImportSelection)
        #expect(store.checklists.isEmpty)
    }

    @Test
    func storeIsByteIdenticalAfterCancel() throws {
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let before = try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "",
            checklists: store.checklists, tombstones: store.tombstones))
        let url = try writeTempFile(try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "",
            checklists: [Checklist(name: "Groceries"), Checklist(name: "New")])))

        viewModel.importFile(at: url)
        viewModel.cancelImport()

        let after = try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion, deviceID: "",
            checklists: store.checklists, tombstones: store.tombstones))
        #expect(before == after)
    }
```

`receivingWhileSheetOpenReplacesStagedFile` (VM-level equivalent of the inbox
test) stages file 1, stages file 2 without cancelling, and asserts
`importCandidates` now describe file 2 and `store.checklists` is still empty.

### Verification
#### Automated
- [x] `make test-unit` passes (new inbox + VM sad-path tests green)
- [x] `bash scripts/test.sh` prints `gate: ok` (full gate: simulator build/test,
      macOS, watchOS, shell tests, shellcheck)

#### Manual
- [ ] Share a plain (non-CheckStitch) `.json` from Files → "Couldn't import"
      alert, no selection sheet
- [ ] Share two different CheckStitch files back-to-back → the second file's
      checklists are the ones offered
- [ ] Cold-start share (app killed) → exactly one selection sheet with the
      file's checklists

---

## Phase 4: Hardening, presentation and on-device verification

The selection sheet presents from the root on macOS as well as iOS, both
selection sheets carry accessibility identifiers, and the installed bundle on a
real iPhone offers CheckStitch for a `.json` shared from Mail and lands on the
selection screen.

### Changes

#### 1. Selection-view accessibility ids
**File**: `CheckStitch/ChecklistSelectionView.swift`
**Action**: verify (ids implemented as parameters in Phase 2)

Confirm import passes `importSelectionRow` / `confirmImportButton` and export
passes `exportSelectionRow` / `confirmExportButton`. No hardcoded ids in the
shared view — a shared id would make the two sheets indistinguishable to the UI
smoke. Nothing further to change unless the compiler/SDK disagrees.

#### 2. Root-only presentation invariant
**File**: `CheckStitch/ContentView.swift`
**Action**: verify

The import `.sheet` and `.fileImporter` are attached to the root
`ContentView` body, alongside the export `.sheet` and `.fileExporter`. Keep the
existing comment explaining why (a sheet-nested file panel never presents its
panel on macOS). Do not move presentation into `SettingsView`.

#### 3. Shell assertion unchanged
**File**: `scripts/tests/run.sh`
**Action**: verify

`documentTypeRegistrationWiresInfoPlist` from Phase 1 stays as the static guard
for `CFBundleDocumentTypes` + both `INFOPLIST_FILE` settings (or the built-plist
variant if the Phase 1 fallback was taken). No new case.

#### 4. Artifacts
**File**: `.pi/orksorksorks/alanvardy-var-1023-import-checklists-through-sharesheet/`
**Action**: modify

Commit the step artifacts for this ticket as they are produced.

### Verification
#### Automated
- [x] `bash scripts/test.sh` prints `gate: ok`
- [x] `make build-mac-signed` succeeds (real macOS app, App Group entitlements embedded)
- [x] `make test-ui` passes (single `CheckStitchUITests` launch/accessibility smoke)
- [x] `bash scripts/tests/run.sh` green including `documentTypeRegistrationWiresInfoPlist`

#### Manual (required — this ticket does not close on static evidence)
- [ ] `bash scripts/run-devices.sh` installs + launches on the real iPhone (and
      the host Mac)
- [ ] On the iPhone: open Mail with a `CheckStitch-yyyy-MM-dd.json` attachment →
      Share → **CheckStitch** is offered → tapping it foregrounds CheckStitch and
      lands on the **selection screen** listing the file's checklists
- [ ] Untick one checklist → Import → only the ticked checklists appear in the
      CheckStitch list
- [ ] Share the same file again from Mail → the selection screen appears again
      (the app is already running)
- [ ] Share a non-CheckStitch `.json` from Files → "Couldn't import", no sheet
- [ ] On the host Mac: Open With → CheckStitch from Finder opens the selection
      sheet (macOS leg of the document type)

**Provider-UTI mitigation (design open risk 2):** if on-device the Share Sheet
does not offer CheckStitch, widen `LSItemContentTypes` to
`["public.json", "public.data"]` in `CheckStitch/Info.plist` and rebuild; the
codec already rejects non-CheckStitch payloads with the existing message. Widen
only if the device check proves it necessary.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` + `bash scripts/tests/run.sh` green; built
  plist carries `CFBundleDocumentTypes`; cold-start and repeat opens import once.
- After Phase 2: session + VM suites green; share arrival and in-app picker both
  show the ticked sheet; unticked conflicts raise nothing.
- After Phase 3: full `bash scripts/test.sh` green; store unchanged on every sad
  path; second arrival wins.
- After Phase 4: `gate: ok`; the on-device Mail-share check observed on the
  installed bundle, with the expected selection screen.

## Files Touched (completeness check)

| File | Phase | Action |
| --- | --- | --- |
| `CheckStitch/Info.plist` | 1 | create |
| `CheckStitch.xcodeproj/project.pbxproj` | 1 | modify (2 config lines) |
| `CheckStitch/SharedImportInbox.swift` | 1 | create |
| `CheckStitch/AppDelegate.swift` | 1 | modify |
| `CheckStitch/ChecklistImportExportViewModel.swift` | 2, 3 | modify |
| `CheckStitch/ContentView.swift` | 1, 2, 3, 4 | modify |
| `CheckStitch/ChecklistImportSession.swift` | 2 | modify |
| `CheckStitch/ChecklistSelectionView.swift` | 2, 4 | create |
| `CheckStitch/ExportChecklistsView.swift` | 2 | modify |
| `CheckStitchTests/SharedImportInboxTests.swift` | 1, 3 | create |
| `CheckStitchTests/ChecklistImportSessionTests.swift` | 2 | modify |
| `CheckStitchTests/ChecklistImportExportViewModelTests.swift` | 2, 3 | modify |
| `scripts/tests/run.sh` | 1, 4 | modify |
| `.pi/orksorksorks/alanvardy-var-1023-import-checklists-through-sharesheet/` | 4 | modify |