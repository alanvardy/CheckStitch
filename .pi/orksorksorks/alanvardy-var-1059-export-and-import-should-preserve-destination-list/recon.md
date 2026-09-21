I have everything needed within budget. Here is the condensed handoff report.

---

# Recon Handoff — VAR-1059: preserve `destinationListIdentifier` across import

Worktree: `/Users/vardy/dev/alanvardy-var-1059-export-and-import-should-preserve-destination-list`

## 1. Files the change touches + established pattern

### `CheckStitch/ChecklistStore.swift` — ROOT OF BUG
`freshCopy()` (lines **173–190**) deliberately drops the field. This is the single choke point for both import paths:
```swift
/// ... deliberately
/// drops the imported `destinationListIdentifier` — a Reminders list id from the
/// source device need not exist here.
private func freshCopy(of checklist: Checklist) -> Checklist {
    Checklist(
        name: checklist.name,
        items: checklist.items.map {
            ChecklistItem(title: $0.title, description: $0.description,
                          modifiedAt: now(), revision: 1, relativeDate: $0.relativeDate,
                          priority: $0.priority)
        },
        prefixesReminderNumbers: checklist.prefixesReminderNumbers,
        modifiedAt: now(),
        revision: 1
    )
}
```
Note: `freshCopy` already copies `prefixesReminderNumbers` (the analogous "copy the extra field" pattern to emulate — see `testPrefixesReminderNumbersSurvivesDuplicateAndImport`). The fix is to add `destinationListIdentifier: checklist.destinationListIdentifier` to this constructor.

Consumers of `freshCopy` (`importInsert` ~**196**, `importReplace` ~**214**) need no change once `freshCopy` carries the field:
```swift
@discardableResult
func importInsert(_ checklist: Checklist, as name: String? = nil) -> UUID {
    var copy = freshCopy(of: checklist)
    copy.name = name ?? Self.uniqueName(basedOn: copy.name, taken: checklists.map(\.name))
    checklists.append(copy)
    save()
    return copy.id
}

@discardableResult
func importReplace(id: UUID, with checklist: Checklist) -> UUID? {
    guard let index = checklists.firstIndex(where: { $0.id == id }) else { return nil }
    let removed = checklists.remove(at: index)
    tombstones.append(ChecklistTombstone(checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1))
    let copy = freshCopy(of: checklist)
    checklists.append(copy)
    save()
    return copy.id
}
```
`duplicate()` (~**162**) also omits it — medium.md marks it OUT OF SCOPE unless the recipe decides otherwise (it mirrors `freshCopy` semantics). `rename`/`setDestination` (~after line 240) manage `destinationListIdentifier` for the local edit path.

### `CheckStitch/ChecklistMerge.swift` — LWW precedent (line ~**84**)
The merge winner branch copies the field, confirming the codec/model field is merge/round-trip safe and the expected "copy destination with the checklist" idiom:
```swift
merged.name = remoteChecklist.name
merged.destinationListIdentifier = remoteChecklist.destinationListIdentifier
merged.prefixesReminderNumbers = remoteChecklist.prefixesReminderNumbers
merged.revision = remoteChecklist.revision
merged.modifiedAt = remoteChecklist.modifiedAt
```

## 2. Codec/envelope already round-trips v4 — NO codec change
`CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`:
- init param line **148**: `destinationListIdentifier: String? = nil,`
- property line **172**: `public var destinationListIdentifier: String?` (doc: `EKCalendar.calendarIdentifier`; `nil` = system default)
- CodingKey line **190**: `case id, name, items, destinationListIdentifier, prefixesReminderNumbers`
- decode line **199**: `let destinationListIdentifier = try container.decodeIfPresent(String.self, forKey: .destinationListIdentifier)` (absent-key tolerant → `nil`, legacy payloads never throw)
- encode line **224**: `try container.encode(destinationListIdentifier, forKey: .destinationListIdentifier)` (unconditional)
- The 4.6.x encode-decode is under `CodingKeys`/`decode`/`encode`; field was added in VAR-991 (no version bump "additive optional field" precedent). Export doc: `CheckStitch/ChecklistExportDocument.swift` uses `ChecklistCodec` so this field flows out already.

## 3. Stale-destination safety net (the `.destinationMissing` pattern)
`CheckStitchCore/Sources/CheckStitchCore/ReminderDestinationTargeting.swift`:
- `resolve` (**31–37**):
```swift
/// Resolves a stored destination to a selectable list. `nil` means "system
/// default". Returns nil when the requested list (or the default) is gone,
/// which the orchestrator turns into `.destinationMissing` before creating anything.
public func resolve(_ identifier: String?) -> ReminderListOption? {
    if let identifier {
        return options.first { $0.id == identifier }
    }
    guard let defaultIdentifier else { return nil }
    return options.first { $0.id == defaultIdentifier }
}
```
- `.destinationMissing` case in `ReminderRunOutcome.errorMessage` (~**77–80**):
```swift
case .destinationMissing: return "That list no longer exists; no reminders were created."
```

`CheckStitch/ChecklistReminders.swift` (`create(from:targeting:)`, lines **26–30**) — deferred-to-first-run validation is the natural net; a preserved but stale id is caught here with **zero-created, all-or-nothing** behavior:
```swift
let snapshot = try await targeting.reminderLists()
guard let destination = snapshot.resolve(checklist.destinationListIdentifier) else {
    // All-or-nothing: validate existence before the first create.
    return .destinationMissing
}
```
So deferring to first run is runtime-safe (surfaced via `errorMessage`/`.destinationMissing`); medium.md leaves validate-at-import vs defer as a `medium-plan` decision.

## 4. Import decode/stage/commit path
`CheckStitch/ChecklistImportSession.swift`:
- `decoded(data:)` (~**100–120**): `ChecklistCodec.classify` → `.loaded`/`.migratable`/throws; **no checklist-building here** — the envelope's `Checklist` objects (already carrying `destinationListIdentifier`) pass straight to candidates.
- `stage(data:)` (~**66–79**): builds `ChecklistImportCandidate(id: checklist.id, checklist: checklist, conflicting:)` — no field stripping; the FILE checklist is carried intact.
- `commit(selectedIDs:)` (~**82–100**): for non-conflicting → `store.importInsert(candidate.checklist)`; conflicts enqueued.
- `decide(...)` (~**120–145**): `.replace` → `store.importReplace(id: conflict.id, with: candidate.checklist)`; `.keepBoth` → `store.importInsert`.

`CheckStitch/ChecklistImportExportViewModel.swift`:
- `importFile(at url:)` (~**106–133**): reads bytes → `ChecklistImportSession(store: store).stage(data:)` → sets `importCandidates`/`importSelection`.
- `commitImport()` (~**136–141**): `session.commit(selectedIDs:)` → `conflict = session.pending.first`.
- `cancelImport()` (~**144–151**): `session.discard()`.
- No checkpoint builds a fresh `Checklist`; the file's checklist is the source of truth end-to-end, so fixing `freshCopy` fully fixes the visible import.

## 5. Tests that must change/extend
- **`CheckStitchTests/ChecklistStoreTests.swift`** — the PRIMARY suit; XCTest (`@MainActor final class ChecklistStoreTests: XCTestCase`, line 6; `#expect`/`test*` XCTest style despite `#expect`-style naming when Swift Testing). Model your new tests on:
  - `testPrefixesReminderNumbersSurvivesDuplicateAndImport` (**1723–1746**) — the exact "import preserves a second-class field through both importInsert and importReplace" template.
  - `testImportInsertGivesFreshIdentityAndPreservesName` (**1843**), `testImportReplaceRemovesLocalAndRecordsWholeChecklistTombstone` (**1896**).
  - `testSetDestinationUpdatesRevisionAndPersists` (**1748**) / `testSetDestinationClearsToDefaultWithNil` (**1764**) — store `destinationListIdentifier` behavior.
  - `makeImportedChecklist()` helper (**1837–1841**) — builds the incoming fixture; extend to set `destinationListIdentifier` (mirrors `ChecklistPacking fixture`).
- **`CheckStitchTests/ChecklistImportSessionTests.swift`** (`struct ChecklistImportSessionTests`, line 7) — stage/commit/decide path; add/assert field survives a staged → committed import.
- **`CheckStitchTests/ChecklistImportExportViewModelTests.swift`** (`struct ChecklistImportExportViewModelTests`, line 8) — end-to-end import via VM (`importFile`/`commitImport`); extend to assert destination preserved.
- **`CheckStitchTests/ChecklistExportTests.swift`** — export→import round-trip; confirm destination is in the encoded document (v4 already encodes it, so may be verification-only).
- **`CheckStitchTests/ReminderListsSnapshotTests.swift`** (`struct ReminderListsSnapshotTests`, line 6) — `resolve()`/`.destinationMissing`; consider a stale-imported-id case.
- **`CheckStitchTests/WatchChecklistStoreTests.swift`** (XCTest store suite) — `testSetDestination…Persists` lines 197–200 already asserts store persistence; may need a Watch-side import-preservation twin.

`CheckStitchTests/TestFixtures.swift` fakes relevant to store/import/run:
- `InMemoryChecklistSync: ChecklistSyncing` (**105–134**) — fake backing store/coordinator persistence.
- `SpyReminderDestination: ReminderDestinationTargeting` (**56–**) — `lists: ReminderListsSnapshot`, `accessGranted`, for run-path `.destinationMissing` tests.
- `SpyReminderCreator`, `InMemoryObservation`, `FakeChecklistSyncTransport`, `SpyChecklistRunner` (**185–193**). Unit suites use `@MainActor` and `@testable import CheckStitchCore`.

## 6. Build/test/lint commands + boundary check
- Fast verify: **`make test-unit`** — `xcodebuild -scheme … -only-testing:CheckStitchTests CODE_SIGNING_ALLOWED=NO` on `platform=macOS` (`Makefile` 69–81; `test:` = `test-unit test-ui`).
- Full gate: **`bash scripts/test.sh`** — `make build`(sim) → headless pre-boot → `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → `shellcheck scripts/*.sh`; prints `gate: ok`.
- All compiling legs use `WARNINGS_AS_ERRORS` (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`); a compiler warning fails the gate.
- New files under `CheckStitch/` need **no** `project.pbxproj` edit (`PBXFileSystemSynchronizedRootGroup`).

**Boundaries:** 
- Schema/codec: **no change** — v4 already encodes `destinationListIdentifier` (additive optional, absent-key tolerant). No migration/version bump.
- **API**: no public API/signature change (`freshCopy` is private; import/run signatures unchanged).
- **UI**: none — imported checklist keeps the user's destination; stale ids surface via existing `.destinationMissing` messaging at first run. No new UI strings.
- **Platform delta** (watch/`CheckStitchWatch` reuses `CheckStitchCore`, plus `ChecklistStore` shared): the `freshCopy` field copy applies on both, watch suite twin likely needed.
- Decision to lock: **validate-at-import vs defer-to-first-run** for the stale-id edge case — medium.md prescribes deferral consistency with `ChecklistMerge`/`ChecklistReminders` (recommended: defer; `.destinationMissing` net already exists); keep `duplicate()` out of scope unless recipe says otherwise.

## Explicit gap
I did not read the full bodies of `ChecklistExportTests.swift` / `ChecklistImportExportViewModelTests.swift` suite contents or `scripts/test.sh` guts (only `AGENTS.md`/`Makefile` for commands) within budget; paths and names above are exact.