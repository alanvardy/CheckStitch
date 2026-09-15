# Implementation Plan

## Overview

Add JSON export (multi-select → `CheckStitch-yyyy-MM-dd.json` via `.fileExporter`) and
JSON import (`.fileImporter` → codec decode → per-conflict Replace / Keep Both /
Keep Existing) to CheckStitch, reusing `ChecklistCodec` so an export is a valid
payload and the round trip is lossless. Every imported mutation goes through
`ChecklistStore`, so a replace records a tombstone and pushes via the existing
`save → onChange → schedulePush` chain.

Phases follow `structure.md` exactly: payload/document → store primitives →
import session → SwiftUI surface. Every phase is green (`make test-unit`) before
the next.

> **Deviation from structure (flagged):** the project has a hard localization gate
> (`CheckStitchTests/LocalizationTests.swift`) that requires every entry in
> `CheckStitch/Localizable.xcstrings` to carry six languages and non-English values
> to differ from English. Stage 4 therefore includes a mandatory string-catalog
> task. See "Deviations" at the end.

---

## Phase 1: Export payload + document (pure serialization)

### Changes

#### 1. `ChecklistExport` (core, pure)

**File**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift`
**Action**: create

```swift
import Foundation

/// Serialises a selected subset of checklists as a *document* envelope: version
/// current, no device identity, no tombstones. An export is therefore a valid
/// `ChecklistCodec` payload (`classify == .loaded`) but never resurrects
/// deletions or injects a foreign `deviceID` into a future LWW tie-break.
public enum ChecklistExport {
    public static func envelope(checklists: [Checklist]) -> ChecklistEnvelope {
        ChecklistEnvelope(version: ChecklistCodec.currentVersion,
                          deviceID: "",
                          checklists: checklists,
                          tombstones: [])
    }

    public static func data(checklists: [Checklist]) throws -> Data {
        try ChecklistCodec.encode(envelope(checklists: checklists))
    }

    /// File name stem, no extension — the export panel supplies `.json` from the
    /// content type. Deterministic for a fixed `date`/`calendar`.
    public static func filename(for date: Date = .now, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "CheckStitch-\(formatter.string(from: date))"
    }
}
```

#### 2. `ChecklistExportDocument` (app layer)

**File**: `CheckStitch/ChecklistExportDocument.swift`
**Action**: create

`FileDocument` lives in the app target, not Core, because Core has no SwiftUI.

```swift
import CheckStitchCore
import SwiftUI
import UniformTypeIdentifiers

/// In-memory export document: the codec-encoded envelope bytes plus a JSON content
/// type. Reading only satisfies the protocol — the app never opens a document this
/// way (import goes through `.fileImporter`).
struct ChecklistExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(checklists: [Checklist]) throws {
        self.data = try ChecklistExport.data(checklists: checklists)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
```

#### 3. Tests

**File**: `CheckStitchTests/ChecklistExportTests.swift`
**Action**: create — XCTest `@MainActor final class`, mirroring `ChecklistCodecTests.swift`
(`import XCTest`, `@testable import CheckStitch`, `import CheckStitchCore`).

Fixture helper in the file (locally scoped, not `TestFixtures.swift`):

```swift
private func makeChecklists() -> [Checklist] {
    [Checklist(name: "Groceries", items: [
        ChecklistItem(title: "Milk", description: "2%", relativeDate: 1),
        ChecklistItem(title: "Eggs"),
    ]),
    Checklist(name: "Packing", items: [ChecklistItem(title: "Socks")]),
    Checklist(name: "Third", items: [ChecklistItem(title: "Unused")])]
}
```

Tests (XCTest names):

- `testExportOfSubsetRoundTripsThroughCodec` — select 2 of 3; `data =
  try ChecklistExport.data(checklists: selected)`; `guard case .loaded(let env)
  = ChecklistCodec.classify(data) else { XCTFail; return }`; assert
  `env.checklists == selected` (names, item titles, `itemOrder`,
  `relativeDate`), `env.deviceID == ""`, `env.tombstones.isEmpty`.
- `testExportEmptySelectionClassifiesLoadedWithNoChecklists` — assert
  `case .loaded` and `env.checklists.isEmpty`.
- `testFilenameIsStableForFixedDate` — fixed UTC `Calendar`, date
  `2026-09-14 12:00Z`, expect `"CheckStitch-2026-09-14"`.
- `testFileWrapperCarriesEncodedBytes` — `let doc = try
  ChecklistExportDocument(checklists: selected)`; `let wrapper = try
  doc.fileWrapper(configuration: .init())`; assert `wrapper.regularFileContents ==
  try ChecklistExport.data(checklists: selected)` and that the bytes classify
  `.loaded`.

### Verification

#### Automated
- [x] `make test-unit` passes (new `ChecklistExportTests` + all existing suites)
- [x] `ChecklistExportTests` show `.loaded` for export bytes and empty-selection export

#### Manual
- [ ] None — pure serialization, fully covered by unit tests.

---

## Phase 2: Store import primitives (data access)

### Changes

#### 1. `ChecklistStore` — conflict lookup, insert, replace, fresh-copy helper

**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify — add the following members (place `conflictingChecklist`
near `checklist(id:)`, the primitives near `duplicate(id:name:)`, `freshCopy`
next to the primitives). `sameName`/`uniqueName` stay `private`.

```swift
/// The first checklist whose name collides with `name` under the store's
/// trimmed, case-insensitive comparison, or `nil` when the name is free. The
/// import flow's conflict primitive — `sameName` stays private.
func conflictingChecklist(named name: String) -> Checklist? {
    checklists.first { Self.sameName($0.name, name) }
}

/// Fresh local identity for imported content: new checklist AND item UUIDs,
/// `revision: 1`, stamped now. Mirrors `duplicate`'s semantics and deliberately
/// drops the imported `destinationListIdentifier` — a Reminders list id from the
/// source device need not exist here.
private func freshCopy(of checklist: Checklist) -> Checklist {
    Checklist(
        name: checklist.name,
        items: checklist.items.map {
            ChecklistItem(title: $0.title, description: $0.description,
                          modifiedAt: now(), revision: 1, relativeDate: $0.relativeDate)
        },
        modifiedAt: now(),
        revision: 1
    )
}

/// Inserts imported content as a new local checklist. The name is disambiguated
/// through `uniqueName` (a no-op for a genuinely free name), which is the
/// non-destructive "Keep Both" path; pass `name` to force one. Never re-enters
/// the LWW merge. Returns the new id.
@discardableResult
func importInsert(_ checklist: Checklist, as name: String? = nil) -> UUID {
    var copy = freshCopy(of: checklist)
    copy.name = name ?? Self.uniqueName(basedOn: copy.name, taken: checklists.map(\.name))
    checklists.append(copy)
    save()
    return copy.id
}

/// Replaces an existing checklist with imported content. Records the same
/// whole-checklist tombstone `delete(id:)` does (`itemID: nil`,
/// `revision + 1`) but commits delete + insert in a single `save()`, so a
/// replace is one push. Returns the new id, or `nil` when the local checklist
/// no longer exists (silent no-op, mirroring `delete`).
@discardableResult
func importReplace(id: UUID, with checklist: Checklist) -> UUID? {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return nil }
    let removed = checklists.remove(at: index)
    tombstones.append(ChecklistTombstone(
        checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
    let copy = freshCopy(of: checklist)
    checklists.append(copy)
    save()
    return copy.id
}
```

No `deviceID` stamping; imported checklists stay local.

#### 2. Tests

**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify — append tests to the existing `@MainActor final class`,
using the file's `makeDefaults()` / `makeStore(defaults:)` helpers and the
`makeStore(... textEditDelay: nil)` fast path (so assertions can read back disk).

Add a fixture helper at the class scope:

```swift
/// An "imported" checklist with non-default identity, so freshness is provable.
private func makeImportedChecklist(name: String = "Groceries",
                                   items: [String] = ["Milk", "Eggs"]) -> Checklist {
    Checklist(name: name,
              items: items.map { ChecklistItem(title: $0, description: "\($0) notes", relativeDate: 1) },
              modifiedAt: Date(timeIntervalSince1970: 100), revision: 7)
}
```

Tests (XCTest names):

- `testImportInsertGivesFreshIdentityAndPreservesName` — import into an empty
  store; new id differs from source id; `revision == 1`; item ids all differ from
  the source's; item count/titles/`description`/`relativeDate` preserved;
  `tombstones` empty; reload from the same defaults still shows 1 checklist.
- `testImportInsertDisambiguatesNameAutomaticallyAndViaOverride` — create
  `"Groceries"`, then `importInsert(imported)` → name `"Groceries 2"`; then
  `importInsert(imported, as: "Custom")` → name `"Custom"`.
- `testImportInsertFiresOnChange` — `store.onChange = { changes += 1 }`;
  one `importInsert` → `changes == 1`.
- `testImportReplaceRemovesLocalAndRecordsWholeChecklistTombstone` — create
  local `"Groceries"` (id `L`); `importReplace(id: L, with: importedNamed("Groceries", 2 items))`;
  assert one checklist remains, new id `!= L`, name `"Groceries"`, `revision == 1`;
  one tombstone with `checklistID == L`, `itemID == nil`, `revision == 2`;
  `tombstones.first?.deletedAt` equals the store's injected clock if used
  (otherwise skip the date assertion).
- `testImportReplaceUnknownIdIsNoOp` — `XCTAssertNil(store.importReplace(id:
  UUID(), with: makeImportedChecklist()))`; checklists and tombstones unchanged.
- `testConflictingChecklistMatchesTrimmedCaseInsensitiveName` — create
  `"Groceries"`; non-nil for `"groceries"` and `" groceries "` and (optionally)
  `"GROCERIES"`; `nil` for `"Milk"`; returns the stored checklist (same id).

### Verification

#### Automated
- [x] `make test-unit` passes; new store tests green
- [x] Existing `ChecklistStoreTests` (tombstones, merge, `onChange`) unchanged and green

#### Manual
- [ ] None.

---

## Phase 3: Import session (business logic)

### Changes

#### 1. `ChecklistImportSession`

**File**: `CheckStitch/ChecklistImportSession.swift`
**Action**: create

```swift
import CheckStitchCore
import Foundation

/// A blocking, pre-mutation import failure. Plain-English `message` mirrors
/// `ReminderRunOutcome.errorMessage` (mapped in core so it is unit-testable and
/// not a localized-catalog key).
enum ChecklistImportError: Error, Equatable {
    case unreadable
    case unsupportedVersion

    var message: String {
        switch self {
        case .unreadable: return "This file isn't a CheckStitch export."
        case .unsupportedVersion: return "This file was created by a newer version of CheckStitch."
        }
    }
}

/// One decoded checklist presented to the import flow. `conflicting` is the
/// local checklist it collides with, or `nil` when it was inserted immediately.
struct ChecklistImportCandidate: Identifiable, Equatable {
    let id: UUID
    let checklist: Checklist
    let conflicting: Checklist?
}

enum ImportDecision: Equatable { case replace, keepBoth, keepExisting }

struct ImportSummary: Equatable {
    var inserted = 0
    var replaced = 0
    var keptBoth = 0
    var keptExisting = 0
}

/// Turns raw file bytes into an ordered candidate list and applies the user's
/// per-conflict decisions to the store. `@Observable` so the SwiftUI conflict
/// dialog can track `pending`.
@MainActor
@Observable
final class ChecklistImportSession {
    private let store: ChecklistStore
    private let now: () -> Date

    /// Conflicts awaiting a decision, in file order.
    private(set) var pending: [ChecklistImportCandidate] = []
    private(set) var summary = ImportSummary()

    init(store: ChecklistStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// Decodes `data`, inserts every non-conflicting checklist immediately
    /// (`importInsert`), and returns all candidates in file order. Throws — and
    /// has mutated nothing — for a payload this build cannot read or does not
    /// understand. Resets prior state, so one session per file is idempotent.
    @discardableResult
    func prepare(data: Data) throws -> [ChecklistImportCandidate] {
        let incoming: [Checklist]
        switch ChecklistCodec.classify(data) {
        case .loaded(let envelope):
            incoming = envelope.checklists
        case .migratable(let from, let envelope):
            incoming = envelope.checklists.map { checklist in
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

        pending = []
        summary = ImportSummary()

        var candidates: [ChecklistImportCandidate] = []
        for checklist in incoming {
            if let conflict = store.conflictingChecklist(named: checklist.name) {
                let candidate = ChecklistImportCandidate(
                    id: UUID(), checklist: checklist, conflicting: conflict)
                pending.append(candidate)
                candidates.append(candidate)
            } else {
                store.importInsert(checklist)
                summary.inserted += 1
                candidates.append(ChecklistImportCandidate(
                    id: UUID(), checklist: checklist, conflicting: nil))
            }
        }
        return candidates
    }

    /// Applies one conflict decision and removes the candidate from the queue.
    /// A replace whose local target vanished is counted as neither.
    func decide(_ decision: ImportDecision, for candidateID: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == candidateID }) else { return }
        let candidate = pending.remove(at: index)
        switch decision {
        case .replace:
            if let conflict = candidate.conflicting,
               store.importReplace(id: conflict.id, with: candidate.checklist) != nil {
                summary.replaced += 1
            }
        case .keepBoth:
            store.importInsert(candidate.checklist)   // auto-disambiguates via uniqueName
            summary.keptBoth += 1
        case .keepExisting:
            summary.keptExisting += 1
        }
    }
}
```

> Note: `.keepBoth` does **not** pass an explicit name. `importInsert`'s internal
> `uniqueName` already disambiguates against the live local list, and
> `uniqueName` stays private per the structure's cross-cutting note — this is the
> same observable behaviour the structure's "`importInsert(as: uniqueName)`"
> describes.

#### 2. Tests

**File**: `CheckStitchTests/ChecklistImportSessionTests.swift`
**Action**: create — Swift Testing struct, `@MainActor`, `import CheckStitchCore`,
`import Foundation`, `import Testing`, `@testable import CheckStitch`. Reuse
`makeIsolatedDefaults()` from `TestFixtures.swift` and construct stores with
`ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)`.

Per-test helpers:

```swift
private func makeSession() -> (ChecklistImportSession, ChecklistStore) {
    let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
    return (ChecklistImportSession(store: store), store)
}

private func payload(_ checklists: [Checklist], version: Int = ChecklistCodec.currentVersion) throws -> Data {
    try ChecklistCodec.encode(ChecklistEnvelope(version: version, deviceID: "", checklists: checklists))
}
```

Tests (Swift Testing, behaviour names, `#expect(..., "message")`):

- `prepareInsertsNonConflictingCandidates` — payload with `[A, B]`; `candidates.count == 2`;
  `store.checklists.map(\.name) == ["A", "B"]`; `session.summary.inserted == 2`;
  `session.pending.isEmpty`.
- `prepareFlagsConflictAndLeavesItUninserted` — store has local `"Groceries"`;
  payload with `"groceries"`; `pending.count == 1`; `pending.first?.conflicting?.name == "Groceries"`;
  `store.checklists.count == 1`; `summary.inserted == 0`.
- `unsupportedVersionThrowsAndMutatesNothing` — store with one local; payload
  version `ChecklistCodec.currentVersion + 1`;
  `#expect(throws: ChecklistImportError.unsupportedVersion) { try session.prepare(data: data) }`;
  store count unchanged, pending empty.
- `unreadableThrowsAndMutatesNothing` — `Data("not json".utf8)`;
  `#expect(throws: ChecklistImportError.unreadable) { ... }`; store unchanged.
- `migratablePayloadIsAccepted` — version `1` payload (and/or `2`) inserts
  via the migration helpers (assert count).
- `replaceTombstonesAndSwaps` — local `"Groceries"` id `L`; prepare conflict;
  `session.decide(.replace, for: candidateID)`; one checklist, new id `!= L`,
  name `"Groceries"`, `revision == 1`; one whole-checklist tombstone with
  `checklistID == L`, `itemID == nil`, `revision == 2`; `summary.replaced == 1`;
  `pending.isEmpty`.
- `keepBothDisambiguates` — `decide(.keepBoth, ...)`;
  `store.checklists.map(\.name) == ["Groceries", "Groceries 2"]`;
  `summary.keptBoth == 1`.
- `keepExistingLeavesLocalIntact` — `decide(.keepExisting, ...)`; store count 1,
  name `"Groceries"`, `tombstones.isEmpty`; `summary.keptExisting == 1`.
- `importingSameFileTwiceIsStable` — empty store; `prepare` file with `[A]` →
  inserted 1, pending empty; `prepare` the same bytes again → `pending.count == 1`,
  `summary.inserted == 0`; `decide(.keepExisting, ...)`; store still exactly one
  `"A"`.

### Verification

#### Automated
- [x] `make test-unit` passes; session, error-path, and import-twice tests green
- [x] Error paths leave `store.checklists`/`store.tombstones` untouched

#### Manual
- [ ] None.

---

## Phase 4: SwiftUI surface + localization (presentational)

### Changes

#### 1. Export sheet

**File**: `CheckStitch/ExportChecklistsView.swift`
**Action**: create

```swift
import CheckStitchCore
import SwiftUI

/// Multi-select sheet. Export hands the selection back to the root view, which
/// owns `.fileExporter` (a sheet-nested exporter never presents its panel on macOS).
struct ExportChecklistsView: View {
    @Environment(ChecklistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<UUID>
    let onExport: () -> Void

    /// Pure, so the disable state is unit-testable without a live hierarchy.
    var canExport: Bool { !selection.isEmpty }

    /// Pure toggle helper, exposed for tests.
    static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID> {
        var next = selection
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Checklists").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            Text("Select the checklists to include.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            List(store.checklists) { checklist in
                Button {
                    selection = Self.toggled(selection, id: checklist.id)
                } label: {
                    HStack {
                        Image(systemName: selection.contains(checklist.id)
                              ? "checkmark.circle.fill" : "circle")
                        Text(checklist.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exportSelectionRow")
            }
            Button("Export") { onExport() }
                .disabled(!canExport)
                .accessibilityIdentifier("confirmExportButton")
                .padding()
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
```

#### 2. `ContentView` wiring

**File**: `CheckStitch/ContentView.swift`
**Action**: modify — imports, state, entry points, root panels, dialogs.

Add `import UniformTypeIdentifiers` (alongside the existing imports; leave the
duplicate `import CheckStitchCore` line untouched).

Add state near the other `@State` properties:

```swift
@State private var isShowingExport = false
@State private var exportSelection: Set<UUID> = []
@State private var exportDocument: ChecklistExportDocument?
@State private var isExporting = false
@State private var isImporting = false
@State private var importSession: ChecklistImportSession?
@State private var conflict: ChecklistImportCandidate?
@State private var importErrorMessage: String?
@State private var exportErrorMessage: String?
```

macOS entry points — inside the existing `#if os(macOS) .toolbar { ... }`, add
before the settings item:

```swift
ToolbarItem(placement: .primaryAction) { exportButton }
ToolbarItem(placement: .primaryAction) { importButton }
```

iOS entry point — change the existing `.overlay(alignment: .topTrailing)` body
from `settingsButton` to a stack (keeping the `path.isEmpty` guard and the same
padding):

```swift
.overlay(alignment: .topTrailing) {
    if path.isEmpty {
        VStack(spacing: 8) {
            settingsButton
            dataMenuButton
        }
        .padding(.top, 8)
        .padding(.trailing, 12)
    }
}
```

New controls (mirror `settingsButton`'s iOS `CardPlate` styling for
`dataMenuButton`; simple labels on macOS):

```swift
private var exportButton: some View {
    Button { beginExport() } label: {
        Label("Export", systemImage: "square.and.arrow.up")
    }
    .accessibilityIdentifier("exportButton")
}

private var importButton: some View {
    Button { isImporting = true } label: {
        Label("Import", systemImage: "square.and.arrow.down")
    }
    .accessibilityIdentifier("importButton")
}

#if os(iOS)
private var dataMenuButton: some View {
    Menu {
        Button("Export") { beginExport() }
        Button("Import") { isImporting = true }
    } label: {
        Image(systemName: "ellipsis")
            .font(.title2.weight(.semibold))
            .foregroundStyle(CardPlate.iconForeground(for: colorScheme))
            .frame(width: 52, height: 52)
            .background {
                RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                    .fill(CardPlate.iconPlateFill(for: colorScheme))
            }
            .overlay(
                RoundedRectangle(cornerRadius: CardPlate.cornerRadius)
                    .stroke(.tint, lineWidth: 2)
            )
            .contentShape(Rectangle())
    }
    .accessibilityLabel("Import and export")
    .accessibilityIdentifier("dataMenuButton")
}
#endif
```

Root-level presentation modifiers — attach to the outer `ZStack` (never inside
the sheet/popover), after the existing `.alert("Couldn't create reminders", ...)`:

```swift
.sheet(isPresented: $isShowingExport) {
    ExportChecklistsView(selection: $exportSelection) { exportSelected() }
}
.fileExporter(isPresented: $isExporting,
              document: exportDocument,
              contentType: .json,
              defaultFilename: ChecklistExport.filename()) { result in
    if case .failure(let error) = result { exportErrorMessage = error.localizedDescription }
}
.fileImporter(isPresented: $isImporting,
              allowedContentTypes: [.json]) { result in
    switch result {
    case .success(let url): importFile(at: url)
    case .failure(let error): importErrorMessage = error.localizedDescription
    }
}
.confirmationDialog("Name conflict",
                    isPresented: conflictPresented,
                    presenting: conflict) { candidate in
    Button("Replace") { choose(.replace) }
    Button("Keep Both") { choose(.keepBoth) }
    Button("Keep Existing", role: .cancel) { choose(.keepExisting) }
} message: { candidate in
    Text("“\(candidate.checklist.name)” already exists.")
}
```

Error alerts — attach the import alert to the inner `NavigationStack` and the
export alert to the outer `ZStack` so neither shares a view with the existing
reminders alert:

```swift
// on the NavigationStack:
.alert("Couldn't import",
       isPresented: Binding(get: { importErrorMessage != nil },
                            set: { if !$0 { importErrorMessage = nil } })) {
    Button("OK", role: .cancel) {}
} message: { Text(importErrorMessage ?? "") }

// on the ZStack:
.alert("Couldn't export",
       isPresented: Binding(get: { exportErrorMessage != nil },
                            set: { if !$0 { exportErrorMessage = nil } })) {
    Button("OK", role: .cancel) {}
} message: { Text(exportErrorMessage ?? "") }
```

Helpers (in an `extension ContentView` or the existing private helper area):

```swift
private func beginExport() {
    exportSelection = []
    isShowingExport = true
}

private func exportSelected() {
    isShowingExport = false
    let selected = store.checklists.filter { exportSelection.contains($0.id) }
    guard !selected.isEmpty else { return }
    do {
        exportDocument = try ChecklistExportDocument(checklists: selected)
        isExporting = true
    } catch {
        exportErrorMessage = error.localizedDescription
    }
}

private func importFile(at url: URL) {
    // Security-scoped URLs require an access/stop pair around the read; a
    // missing pair silently yields unreadable data on device.
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    do {
        let data = try Data(contentsOf: url)
        let session = ChecklistImportSession(store: store)
        try session.prepare(data: data)
        importSession = session
        conflict = session.pending.first
    } catch let error as ChecklistImportError {
        importErrorMessage = error.message
    } catch {
        importErrorMessage = "This file isn't a CheckStitch export."
    }
}

/// `conflict` is a snapshot of `pending.first`; each decision clears it before
/// advancing, so SwiftUI's own dismissal (setter fires `false`) cannot
/// double-handle the next candidate.
private var conflictPresented: Binding<Bool> {
    Binding(
        get: { conflict != nil },
        set: { presented in
            guard !presented, let current = conflict else { return }
            conflict = nil
            importSession?.decide(.keepExisting, for: current.id)
            advanceConflict()
        }
    )
}

private func choose(_ decision: ImportDecision) {
    guard let current = conflict else { return }
    conflict = nil
    importSession?.decide(decision, for: current.id)
    advanceConflict()
}

/// Re-presents after the current dismissal completes, so the next conflict in
/// the FIFO queue is shown until the queue is empty.
private func advanceConflict() {
    DispatchQueue.main.async {
        conflict = importSession?.pending.first
    }
}
```

No separate `ImportConflictsView.swift` — the dialog is inlined in `ContentView`
(structure explicitly allowed "new, or inlined").

#### 3. String catalog (required by the localization gate)

**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify — add one `strings` entry per key below, matching the existing
entry shape (`"extractionState": "manual"`, each language a `stringUnit` with
`"state": "translated"`). Template:

```json
"Export": {
  "extractionState": "manual",
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "Export" } },
    "fr": { "stringUnit": { "state": "translated", "value": "Exporter" } },
    "es": { "stringUnit": { "state": "translated", "value": "Exportar" } },
    "de": { "stringUnit": { "state": "translated", "value": "Exportieren" } },
    "ja": { "stringUnit": { "state": "translated", "value": "書き出す" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "导出" } }
  }
}
```

All twelve new keys and their values (English key → the five non-English values;
`en` repeats the key):

| Key (en) | fr | es | de | ja | zh-Hans |
|---|---|---|---|---|---|
| `Export` | Exporter | Exportar | Exportieren | 書き出す | 导出 |
| `Import` | Importer | Importar | Importieren | 読み込む | 导入 |
| `Export Checklists` | Exporter les listes | Exportar listas | Checklisten exportieren | チェックリストを書き出す | 导出清单 |
| `Select the checklists to include.` | Sélectionnez les listes à inclure. | Selecciona las listas que quieres incluir. | Wähle die Checklisten zum Exportieren aus. | 含めるチェックリストを選択してください。 | 选择要包含的清单。 |
| `Couldn't import` | Importation impossible | No se pudo importar | Importieren fehlgeschlagen | 読み込めませんでした | 无法导入 |
| `Couldn't export` | Exportation impossible | No se pudo exportar | Exportieren fehlgeschlagen | 書き出せませんでした | 无法导出 |
| `Name conflict` | Conflit de nom | Conflicto de nombre | Namenskonflikt | 名前の重複 | 名称冲突 |
| `“%@” already exists.` | « %@ » existe déjà. | «%@» ya existe. | „%@“ ist bereits vorhanden. | 「%@」はすでに存在します。 | “%@”已存在。 |
| `Replace` | Remplacer | Reemplazar | Ersetzen | 置き換える | 替换 |
| `Keep Both` | Garder les deux | Conservar ambas | Beide behalten | 両方保持 | 两者都保留 |
| `Keep Existing` | Garder l'existante | Conservar la existente | Vorhandene behalten | 既存を保持 | 保留现有 |
| `Import and export` | Importer et exporter | Importar y exportar | Importieren und exportieren | 読み込みと書き出し | 导入和导出 |

The interpolated message key must be exactly `“%@” already exists.` (curly
quotes `U+201C`/`U+201D`), matching `Text("“\(candidate.checklist.name)” already exists.")`.

#### 4. Localization fixture

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify — append the twelve keys above to the `"App"` entry of
`requiredKeys` (keeps `everyRequiredKeyIsPresent` guarding them). Existing
`Cancel`/`OK` are already listed.

#### 5. Entitlement (conditional)

**File**: `CheckStitch/AppGroup.entitlements`
**Action**: modify **only if** the signed macOS build's save/open panel fails
without it — add `com.apple.security.files.user-selected.read-write` (`<true/>`).
If the panel works, make no change. `make build-mac` is unsigned and cannot
observe this; `make build-mac-signed` is the check.

#### 6. View tests

**File**: `CheckStitchTests/ExportChecklistsViewTests.swift`
**Action**: create — Swift Testing struct, `@MainActor`, mirroring
`ViewRenderTests.swift` (uses `ImageRenderer`).

- `exportViewRendersAndDerivesCanExportFromSelection` — store with one created
  checklist; build `ExportChecklistsView(selection: .constant([])) {}` and a
  filled-selection variant; assert `renders(view.environment(store))` for both;
  `empty.canExport == false`, `filled.canExport == true`.
- `toggledAddsAndRemovesSelection` — `ExportChecklistsView.toggled([], id:) == [id]`
  and `toggled([id], id:) == []`.

`Item` note: `ExportChecklistsView` reads `ChecklistStore` from the environment,
so the render helper must apply `.environment(store)` (same as
`ChecklistDetailViewTests`). The local `renders` helper is copied from
`ViewRenderTests` (`#if os(macOS)` / `ImageRenderer`).

No change to `CheckStitchUITests/CheckStitchUITests.swift` — the smoke test's
`settingsButton`/`createChecklistButton`/row-action assertions still hold.

### Verification

#### Automated
- [x] `make test-unit` passes (view tests + all localization suites green)
- [ ] `bash scripts/test.sh` prints `gate: ok` (runs `make build`, `make test`,
  `make build-mac`, `make watch-build`, `bash scripts/tests/run.sh`, `shellcheck`)

#### Manual
- [ ] `make build-mac-signed` succeeds with no entitlement change; launch the app,
  Export → multi-select 2 of 3 → save → the file is named `CheckStitch-<date>.json`
  and its bytes classify `.loaded` (drop it into a scratch `ChecklistCodec` check or
  just re-import it).
- [ ] macOS: Import the exported file on a store that already owns a same-named
  checklist → the conflict dialog appears per conflict, each choice behaves
  (Replace swaps + records a tombstone; Keep Both yields `"<name> 2"`; Keep
  Existing leaves the local copy).
- [ ] macOS: delete/rename a checklist, then confirm the store pushes (iCloud
  sync status stays quiet); an import with no conflicts inserts immediately.
- [ ] Import a corrupt file (`echo hi > /tmp/bad.json`) and a future-version file
  → "This file isn't a CheckStitch export." / "…newer version…" alert; nothing
  changes in the list.
- [ ] Device/simulator run (`bash scripts/run-devices.sh`): the file panel opens,
  the security-scoped read succeeds, and the same export→import loop works.
- [ ] iOS: the floating `…` plate renders beside Settings, is hidden on a pushed
  screen, and the accessibility audit in the UI smoke stays green.

---

## Final gate

- [ ] `make test-unit` (fast loop) green
- [ ] `bash scripts/test.sh` → `gate: ok`
- [ ] `make build-mac-signed` manual panel check complete
- [ ] No `project.pbxproj` edit was needed (synchronized groups pick up new files)

---

## Deviations from `structure.md` (and why)

1. **Added string-catalog + `LocalizationFixtures` work in Stage 4.** Not in the
   structure outline, but the project gate (`LocalizationTests`) requires every
   `Localizable.xcstrings` entry to carry six languages with non-English values
   differing from English. New SwiftUI string literals would otherwise fail the
   gate. `ChecklistImportError.message` stays plain English like the existing
   `ReminderRunOutcome.errorMessage`, so it needs no catalog entry.
2. **No `ImportConflictsView.swift`** — the structure allowed "new, or inlined";
   the dialog is inlined in `ContentView`.
3. **`.keepBoth` does not pass an explicit name** to `importInsert`; the store's
   private `uniqueName` disambiguates internally, honouring the structure's
   "don't widen `uniqueName`" cross-cutting note.
4. **`freshCopy` drops `destinationListIdentifier`**, mirroring
   `duplicate(id:name:)`. The structure did not state this; it avoids importing a
   Reminders list identifier that need not exist on this device.
5. **Import errors use one shared `ChecklistImportError.message` string**, mapped
   after the `ReminderRunOutcome` precedent; only the alert *titles* and buttons
   are localized keys.