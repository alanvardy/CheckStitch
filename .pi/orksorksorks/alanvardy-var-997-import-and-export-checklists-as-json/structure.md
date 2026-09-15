# Structure Outline

## Approach

Build the feature bottom-up: a pure export-payload/document layer in `CheckStitchCore`,
then two new store import primitives, then a testable import session that maps a decoded
envelope + user decisions onto those primitives, and finally the SwiftUI surface
(multi-select export sheet, root-level `.fileExporter`/`.fileImporter`, conflict dialogs).
Every layer is green before the next; the UI layer is the first that needs a device/signed build.

---

## Stage 1: Export payload + document (pure serialization)

Builds a document-shaped envelope from a selected subset and wraps it as a `FileDocument`,
reusing `ChecklistCodec.encode` so the bytes are a valid codec payload. Green tests prove
round trip and subset filtering without any UI.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift` (new),
`CheckStitch/ChecklistExportDocument.swift` (new)

**Key changes**:
- `enum ChecklistExport`
  - `static func envelope(checklists: [Checklist]) -> ChecklistEnvelope` — `version: ChecklistCodec.currentVersion`, `deviceID: ""`, `tombstones: []`
  - `static func data(checklists: [Checklist]) throws -> Data` — `ChecklistCodec.encode(envelope)`
  - `static func filename(for date: Date = .now, calendar: Calendar = .current) -> String` — `"CheckStitch-yyyy-MM-dd"`
- `struct ChecklistExportDocument: FileDocument` — `init(checklists: [Checklist]) throws`, `static var readableContentTypes: [UTType]` (`.json`), `fileWrapper(configuration:) throws -> FileWrapper`
  - *Next layer consumes*: the `FileDocument` directly for `.fileExporter`; `ChecklistExport.envelope` is the contract the codec tests assert against.

**Tests** (`ChecklistExportTests.swift`, XCTest `@MainActor`, mirroring `ChecklistCodecTests`):
- selection of 2 of N → `classify(data) == .loaded`, decoded names/items/`itemOrder`/`relativeDate` equal the subset (happy)
- exported envelope carries `deviceID == ""` and `tombstones == []`
- empty selection → `.loaded` with `checklists == []`
- `filename(for:)` is stable for a fixed date
- `FileWrapper` regular-file content equals `ChecklistExport.data(...)`
**Verify**: `make test-unit` green for this stage.

---

## Stage 2: Store import primitives (data access)

Adds explicit insert/replace primitives to `ChecklistStore` that never re-enter the LWW merge,
mirroring `delete(id:)`'s tombstone shape and `duplicate(id:name:)`'s fresh-identity semantics.
Green tests prove tombstone recording, conflict detection, and `save()`/`onChange` firing.

**Files**: `CheckStitch/ChecklistStore.swift`, `CheckStitchTests/ChecklistStoreTests.swift`

**Key changes**:
- `func conflictingChecklist(named: String) -> Checklist?` — first match via existing `sameName` (trimmed, case-insensitive)
- `@discardableResult func importInsert(_ checklist: Checklist, as name: String? = nil) -> UUID` — fresh identity (`freshCopy(of:)`: new checklist + item UUIDs, `revision: 1`, `modifiedAt: now()`), optional disambiguated override for Keep Both, append, `save()`
- `@discardableResult func importReplace(id: UUID, with checklist: Checklist) -> UUID?` — append tombstone `ChecklistTombstone(checklistID: id, itemID: nil, deletedAt: now(), revision: local.revision + 1)`, remove local, insert fresh copy, `save()`
- `private func freshCopy(of: Checklist) -> Checklist` — the single re-identification helper both primitives share
- No `deviceID` stamping; imported checklists stay local
  - *Next layer consumes*: `conflictingChecklist`, `importInsert`, `importReplace`.

**Tests** (`ChecklistStoreTests.swift`):
- `importInsert` on a fresh name inserts with new IDs, `revision 1`, name preserved; `onChange` fired
- `importInsert(as:)` uses the passed disambiguated name
- `importReplace` removes the local entry, records a whole-checklist tombstone with `revision + 1`, inserts fresh-ID content
- `importReplace` with unknown id is a no-op returning `nil` (sad path)
- `conflictingChecklist` matches `"Groceries"` / `"groceries"` / `" groceries "` and returns `nil` for a unique name
**Verify**: `make test-unit` green; existing `ChecklistStoreTests` still green (no merge-engine changes).

---

## Stage 3: Import session (business logic)

Turns raw file bytes into an ordered candidate list and applies decisions to the store,
choosing the outcome mapping for `.loaded` / `.migratable` (accept, using existing migration
helpers) vs `.unsupportedVersion` / `.unreadable` (throw, mutate nothing). Fully testable with
an in-memory store — no UI.

**Files**: `CheckStitch/ChecklistImportSession.swift` (new),
`CheckStitchTests/ChecklistImportSessionTests.swift` (new)

**Key changes**:
- `enum ChecklistImportError: Error { case unreadable, unsupportedVersion }`
- `struct ChecklistImportCandidate: Identifiable { let id: UUID; let checklist: Checklist; let conflicting: Checklist? }`
- `enum ImportDecision { case replace, keepBoth, keepExisting }`
- `@MainActor final class ChecklistImportSession`
  - `init(store: ChecklistStore)`
  - `func prepare(data: Data) throws -> [ChecklistImportCandidate]` — `classify`; `.loaded` → candidates; `.migratable` → map through `seededOrder()`/`migrated(at:)`; unsupported/unreadable → throw with **no store mutation**; non-conflicting candidates inserted immediately via `importInsert`
  - `func decide(_ decision: ImportDecision, for candidateID: UUID)` — `.replace` → `importReplace`, `.keepBoth` → `importInsert(as: uniqueName)`, `.keepExisting` → skip
  - `var pending: [ChecklistImportCandidate]` — FIFO queue of conflicts awaiting a dialog
  - `var summary: ImportSummary` — inserted / replaced / keptBoth / keptExisting counts
  - *Next layer consumes*: `prepare`, `pending`, `decide`, `summary`.

**Tests** (Swift Testing, `@MainActor`): file `prepare` yields candidates; conflict candidate carries the local match; non-conflicting candidates inserted on `prepare`; `.unsupportedVersion` and `"not json"` throw and leave `store.checklists` untouched (sad paths); `.replace` tombstones + swaps; `.keepBoth` disambiguates; `.keepExisting` leaves local intact; importing the same file twice is stable (idempotent counts, no drops beyond the choice).
**Verify**: `make test-unit` green.

---

## Stage 4: SwiftUI surface (presentational)

Wires the session and export document into the two entry points, the root-level file panels,
and the existing confirm/alert primitives. This is the only stage that needs a booted sim and a
signed macOS run.

**Files**: `CheckStitch/ExportChecklistsView.swift` (new), `CheckStitch/ImportConflictsView.swift` (new, or inlined),
`CheckStitch/ContentView.swift`, `CheckStitch/AppGroup.entitlements` (only if signed build proves it)

**Key changes**:
- `struct ExportChecklistsView: View` — sheet with `@State private var selection: Set<UUID>`; rows from `store.checklists`; Export button disabled while empty; builds `ChecklistExportDocument`
- Root modifiers on `ContentView` (never inside the sheet/popover): `.fileExporter(isPresented:document:contentType:defaultFilename:)` and `.fileImporter(isPresented:allowedContentTypes:onCompletion:)`
- Import completion: `startAccessingSecurityScopedResource()` / `defer stop…` around the `Data(contentsOf:)` read, then `session.prepare`
- `.confirmationDialog` driven by `session.pending.first`, buttons Replace / Keep Both / Keep Existing, calling `session.decide`
- `.alert` for `ChecklistImportError` ("This file isn't a CheckStitch export." / "…created by a newer version of CheckStitch.") and for save-panel errors
- Entry points: macOS `.toolbar` items (Export, Import) alongside create/settings; iOS floating `CardPlate` overlay, hidden when the nav path is non-empty
- `AppGroup.entitlements`: add `com.apple.security.files.user-selected.read-write` **only if** the signed build's panel fails without it
  - *Cross-cutting note*: the entitlement and the panel attachment point are only observable at this layer. The serialization contract they depend on is stubbed and proven in Stages 1–3, so a panel failure here cannot mask a data bug.

**Tests**: `ExportChecklistsViewTests.swift` (render + selection toggle / empty-selection disable) in the `ViewRenderTests` style; existing UI smoke unchanged; **manual** `make build-mac-signed` + save/open a file on macOS and a device run (`bash scripts/run-devices.sh`) to exercise the security-scoped read.
**Verify**: `make test-unit`, then full gate `bash scripts/test.sh` prints `gate: ok`, then signed macOS check.

---

## Testing Checkpoints

- After Stage 1: `make test-unit` green; export bytes classify `.loaded`.
- After Stage 2: `make test-unit` green; tombstone + fresh-identity import tests pass, existing store/merge suites untouched.
- After Stage 3: `make test-unit` green; error paths mutate nothing; import-twice stable.
- After Stage 4: `bash scripts/test.sh` → `gate: ok`; `make build-mac-signed` panel manually verified.

## Cross-Cutting Notes

- `sameName` / `uniqueName` are currently private; Stage 2 exposes behavior through
  `conflictingChecklist` and the import primitives rather than widening them.
- No `project.pbxproj` edit needed (`PBXFileSystemSynchronizedRootGroup`).
- No changes to `ChecklistMerge`, `currentVersion`, or the codec format.