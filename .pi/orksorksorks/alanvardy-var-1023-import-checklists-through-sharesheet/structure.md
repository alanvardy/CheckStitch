# Structure Outline

## Approach
Register `public.json` as a document type (`CFBundleDocumentTypes`) and funnel both
OS deliveries — `application(_:open:)` and `.onOpenURL` — through one idempotent
`SharedImportInbox`, then split `ChecklistImportSession` into stage → select →
commit with a shared `ChecklistSelectionView` gating `importInsert` + FIFO
conflicts. Walk the riskiest OS seam first, add the selection semantics, then
harden. One exception to vertical slicing: the Info.plist/`project.pbxproj`
wiring in Phase 1 is horizontal config — it cannot demo alone and rides with the
reception skeleton.

---

## Phase 1: Walking skeleton — an OS share / Open-In reaches the store
A CheckStitch JSON opened from Mail/Files via "Open In" launches CheckStitch and
its checklists are imported (all of them — current `prepare` semantics, no
selection yet). Green tests prove the OS hands us the URL exactly once and the
store gains the file's checklists.

**Files**: `CheckStitch/Info.plist` (new), `CheckStitch.xcodeproj/project.pbxproj`
(Debug+Release `INFOPLIST_FILE`), `CheckStitch/AppDelegate.swift`,
`CheckStitch/SharedImportInbox.swift` (new), `CheckStitch/ContentView.swift`,
`CheckStitch/ChecklistImportExportViewModel.swift`.

**Key changes**:
- `struct SharedImportFile: Identifiable, Equatable { let id: UUID; let url: URL; let displayName: String }` — new
- `@MainActor final class SharedImportInbox` — new: `static let shared`,
  `private(set) var pending: SharedImportFile?`, `func receive(url: URL)`
  (idempotent — dedupe on last-received URL), `func consume() -> SharedImportFile?`
- `AppDelegate.application(_:open:options:) -> Bool` (iOS) and
  `MacAppDelegate.application(_:open urls:)` (macOS) — new, both call
  `SharedImportInbox.shared.receive(url:)`
- `ContentView`: `.onOpenURL { SharedImportInbox.shared.receive(url: $0) }` plus a
  consume-on-appear that calls `importExportVM.importFile(at:)`
- plist keys: `CFBundleDocumentTypes` (`LSItemContentTypes = [public.json]`,
  `CFBundleTypeRole = Viewer`, `LSHandlerRank = Alternate`) and
  `LSSupportsOpeningDocumentsInPlace = true`

**Contract**: `SharedImportInbox`'s API; and "any inbound file is exposed as a
security-scoped `URL` consumed via `importFile(at:)`". Phase 2 leans on the inbox
without touching its internals.

**Tests**: new `SharedImportInboxTests` — `receivesSameURLOnce`,
`coldStartArrivalConsumesOnce`; existing `ChecklistImportExportViewModelTests`
`importFileReadsAndCommitsAll` still green; `scripts/tests/run.sh` adds
`documentTypeRegistrationWiresInfoPlist` (source plist carries
`CFBundleDocumentTypes`; **both** app configs set `INFOPLIST_FILE`).

**Verify**: `make test-unit` and `bash scripts/tests/run.sh` pass; `make build`
then `plutil -p <DerivedData>/…/CheckStitch.app/Info.plist` shows the doc type;
manual Open-In smoke. Fallback if the file/generated plist merge fails:
`INFOPLIST_KEY_*` scalars + generated-file post-process — implementation, not a
design change.

---

## Phase 2: Selection — only the ticked checklists are imported
Any arrival (share **or** in-app picker) shows a checkmark sheet listing the
file's checklists, all ticked; Confirm imports exactly the ticked ones; Cancel
leaves the store untouched. Conflicts are raised only for ticked checklists.

**Files**: `CheckStitch/ChecklistImportSession.swift`,
`CheckStitch/ChecklistImportExportViewModel.swift`,
`CheckStitch/ChecklistSelectionView.swift` (new),
`CheckStitch/ExportChecklistsView.swift`, `CheckStitch/ContentView.swift`,
`CheckStitchTests/ChecklistImportSessionTests.swift`,
`CheckStitchTests/ChecklistImportExportViewModelTests.swift`.

**Key changes**:
- `ChecklistImportCandidate.id` becomes the file's checklist UUID (was a fresh UUID)
- `ChecklistImportSession.stage(data: Data) throws -> [ChecklistImportCandidate]`
  replaces `prepare` — decode + migrate + read-only `store.conflictingChecklist(named:)`
  for display, **no store writes**
- `ChecklistImportSession.commit(selectedIDs: Set<UUID>) -> ImportSummary` — file
  order, re-checks conflict at commit time (authoritative), then `importInsert` /
  FIFO `pending` for selected only
- `ChecklistImportSession.discard()`
- `struct ChecklistSelectionView(title:rows:selection:confirmTitle:onConfirm:onCancel:)`
  + `struct ChecklistSelectionRow: Identifiable { id; name; detail }` +
  `static func toggled(_ selection: Set<UUID>, id: UUID) -> Set<UUID>` — new,
  used by both import and export (`ExportChecklistsView` refactored onto it)
- VM: `importCandidates`, `importSelection`, `isShowingImportSelection`,
  `commitImport()`, `cancelImport()`; `importFile(at:)` stages then presents
- `ContentView` presents the selection sheet from the **root**, not inside `SettingsView`

**Contract**: `stage`/`commit`/`discard`; `ChecklistSelectionView`,
`ChecklistSelectionRow`, `toggled`; the VM's `importCandidates` /
`importSelection` / `commitImport()` / `cancelImport()`.

**Tests**: `ChecklistImportSessionTests` rewritten — `stagingWritesNothingToStore`,
`commitImportsOnlySelected`, `commitSkipsUnselectedConflicts`,
`commitEnqueuesSelectedConflictsInFileOrder`, `discardLeavesStoreUnchanged`,
`unsupportedVersionThrowsBeforeStaging`, `unreadableThrowsBeforeStaging`,
`migratableStagesNormalisedCandidates`, `reImportStability`, `priorityPreserved`;
`ChecklistImportExportViewModelTests` — `importFileStagesAndPresentsSelection`,
`commitImportAppliesTickSelection`, `cancelImportDiscardsStagedFile`,
`emptySelectionCannotConfirm`, and the FIFO `decide` test now commits first.

**Verify**: `make test-unit` green for the session + VM suites; `make build`
(recompiles the new sheet API against the SDK — compiler is the oracle).

---

## Phase 3: Robustness — bad and repeated arrivals never touch the store
A non-CheckStitch or newer-version JSON shows the existing "Couldn't import"
alert with **no** sheet; a second share replaces the pending file; a cold-start
arrival is consumed exactly once; cancel leaves the store byte-identical.

**Files**: `CheckStitch/SharedImportInbox.swift`,
`CheckStitch/ChecklistImportExportViewModel.swift`, `CheckStitch/ContentView.swift`,
`CheckStitchTests/SharedImportInboxTests.swift`,
`CheckStitchTests/ChecklistImportExportViewModelTests.swift`.

**Key changes**:
- `receive(url:)` while a sheet is open replaces `pending` and re-stages (last arrival wins)
- `importFile(at:)` surfaces read/format failures through `importErrorMessage`
  before any staging or sheet presentation
- pending consumed from the root's `.task` so a pre-root arrival reaches the sheet once

**Contract**: public signatures unchanged; behaviour guarantees (idempotent
receive, replace-on-second-arrival, errors write nothing).

**Tests**: `SharedImportInboxTests` — `secondDistinctArrivalReplacesPending`,
`receivingWhileSheetOpenReplacesStagedFile`; VM — `unreadableFileShowsAlertAndNoSheet`,
`unsupportedVersionShowsAlertAndNoSheet`, `storeIsByteIdenticalAfterCancel`.

**Verify**: `make test-unit` green for both suites; then the full gate
`bash scripts/test.sh`.

---

## Phase 4: Hardening, presentation and on-device verification
The selection sheet presents from the root on macOS as well as iOS, both
selection sheets carry accessibility identifiers, and the installed bundle on a
real iPhone offers CheckStitch for a `.json` shared from Mail and lands on the
selection screen.

**Files**: `CheckStitch/ChecklistSelectionView.swift`,
`CheckStitch/ContentView.swift`, `scripts/tests/run.sh`, `.pi/…` artifacts.

**Key changes**:
- accessibility ids on rows/confirm (`importSelectionRow`, `confirmImportButton`)
  mirroring export's
- root-only presentation kept as an invariant (macOS `.fileImporter` is flaky when
  nested in a sheet)
- the Phase 1 plist/config shell assertion stays as the static guard

**Contract**: unchanged; this slice only constrains presentation and adds ids.

**Tests**: `scripts/tests/run.sh documentTypeRegistrationWiresInfoPlist`;
existing `CheckStitchUITests` launch smoke still green.

**Verify**: `bash scripts/test.sh` prints `gate: ok`; `make build-mac-signed`;
`bash scripts/run-devices.sh`, then share a CheckStitch JSON from Mail → the app
appears → selection screen → only ticked checklists present. No closing on static
evidence.

---

## Testing Checkpoints
- After Phase 1: `make test-unit` + `bash scripts/tests/run.sh` green and the built plist carries `CFBundleDocumentTypes`.
- After Phase 2: session + VM suites green; share arrival and in-app picker both show the sheet.
- After Phase 3: full `bash scripts/test.sh` green; store unchanged on every sad path.
- After Phase 4: `gate: ok` and the on-device Mail-share check observed.