# Implementation Plan

## Overview

An imported checklist must keep the Reminders list (destination) chosen when it
was exported. The codec already round-trips `Checklist.destinationListIdentifier`;
the only place it is lost is `ChecklistStore.freshCopy(of:)`, the rebuild used by
both import paths. The fix copies the field there and leaves stale-id handling to
the existing `.destinationMissing` run-path net (preserve, defer to first run).
The bulk of the work is tests at the store, import-session, and view-model seams.

## Locked decisions

- **Stale destination: preserve the id and defer validation to first run.**
  Matches `ChecklistMerge` (last-write-wins copies the field verbatim,
  `ChecklistMerge.swift:84`) and `ChecklistReminders.create` (`resolve` →
  `.destinationMissing`, zero reminders created). No EventKit dependency is
  added to the import session, and the id survives so a list re-created later
  matches again.
- **`duplicate()` is out of scope.** It also omits the field, but medium.md
  scopes this ticket to import only. Do not touch it.
- **No codec/version/migration change.** `destinationListIdentifier` is an
  additive optional key already encoded in v4 (`Checklist.swift` decode/encode
  at ~lines 199/224, absent-key tolerant → `nil`).

---

## Phase 1: Store fix — imported destination survives `freshCopy`

Walking skeleton: the production fix plus store-level proof for both import
primitives and the `nil` default.

### Changes

#### 1. Carry the destination through `freshCopy`
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify

In `freshCopy(of:)` (~line 177), add `destinationListIdentifier` in declaration
order (it sits between `items` and `prefixesReminderNumbers` in `Checklist.init`).
Replace the doc comment, which currently states the field is deliberately dropped.

```swift
    /// Fresh local identity for imported content: new checklist AND item UUIDs,
    /// `revision: 1`, stamped now. Mirrors `duplicate`'s semantics. The imported
    /// `destinationListIdentifier` is carried over so the user's chosen Reminders
    /// list survives; if that list is missing on this device the run path's
    /// existing `.destinationMissing` net reports it before creating anything.
    private func freshCopy(of checklist: Checklist) -> Checklist {
        Checklist(
            name: checklist.name,
            items: checklist.items.map {
                ChecklistItem(title: $0.title, description: $0.description,
                              modifiedAt: now(), revision: 1, relativeDate: $0.relativeDate,
                              priority: $0.priority)
            },
            destinationListIdentifier: checklist.destinationListIdentifier,
            prefixesReminderNumbers: checklist.prefixesReminderNumbers,
            modifiedAt: now(),
            revision: 1
        )
    }
```

`importInsert` (~196) and `importReplace` (~214) need no change — they both call
`freshCopy`. Leave their bodies and `duplicate()` untouched.

#### 2. Store tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify

Extend the existing `makeImportedChecklist` helper (~1836) with a destination
parameter, mirroring how `prefixesReminderNumbers` is exercised:

```swift
    private func makeImportedChecklist(name: String = "Groceries",
                                       items: [String] = ["Milk", "Eggs"],
                                       destination: String? = nil) -> Checklist {
        Checklist(name: name,
                  items: items.map { ChecklistItem(title: $0, description: "\($0) notes", relativeDate: 1) },
                  destinationListIdentifier: destination,
                  modifiedAt: Date(timeIntervalSince1970: 100), revision: 7)
    }
```

Add beside `testPrefixesReminderNumbersSurvivesDuplicateAndImport` (~1723):

```swift
    /// Happy path: the exported destination survives both import primitives and
    /// is persisted, not just held in memory.
    func testDestinationSurvivesImportInsertAndReplace() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let incoming = makeImportedChecklist(destination: "list-a")

        let inserted = store.importInsert(incoming)
        XCTAssertEqual(store.checklist(id: inserted)?.destinationListIdentifier, "list-a")
        XCTAssertEqual(makeStore(defaults: suite.defaults).checklist(id: inserted)?.destinationListIdentifier,
                       "list-a", "the destination is persisted")

        let local = store.create(name: "Trip")
        guard let replaced = store.importReplace(id: local.id, with: incoming) else {
            XCTFail("expected the replace to land")
            return
        }
        XCTAssertEqual(store.checklist(id: replaced)?.destinationListIdentifier, "list-a")
    }

    /// Default/sad path: an import with no chosen destination stays system-default.
    func testImportWithoutDestinationStaysNil() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let inserted = store.importInsert(makeImportedChecklist())

        XCTAssertNil(store.checklist(id: inserted)?.destinationListIdentifier)
    }
```

### Verification
#### Automated
- [x] `make test-unit` passes (XCTest `ChecklistStoreTests`, incl. the two new cases)
- [x] `make build` passes with `WARNINGS_AS_ERRORS` (watch for unused/mismatched argument labels in the edited constructor)

#### Manual
- [ ] Confirm `freshCopy` is the only rebuild used by `importInsert`/`importReplace` and that `duplicate()` is unchanged.

---

## Phase 2: Import surface end-to-end — session and view model

Prove the file-decode → stage → commit path preserves the destination through
both conflict decisions, and that the export boundary already emits it.

### Changes

#### 1. Import session test (insert + replace)
**File**: `CheckStitchTests/ChecklistImportSessionTests.swift`
**Action**: modify

Add beside `priorityPreserved` (~174), modelled on it:

```swift
    /// The imported destination survives the whole stage/commit path through the
    /// plain insert and through a Replace decision. Both rebuild via `freshCopy`.
    @Test
    func destinationPreserved() throws {
        let incoming = Checklist(name: "Groceries", destinationListIdentifier: "list-a")

        let (session, store) = makeSession()
        _ = try session.stage(data: payload([incoming]))
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(store.checklists.first?.destinationListIdentifier == "list-a",
                "insert keeps the payload destination")

        let (replacing, replaceStore) = makeSession()
        replaceStore.create(name: "Groceries")
        _ = try replacing.stage(data: payload([incoming]))
        replacing.commit(selectedIDs: allIDs(replacing.candidates))
        replacing.decide(.replace, for: replacing.pending.first?.id ?? UUID())
        #expect(replaceStore.checklists.first?.destinationListIdentifier == "list-a",
                "replace keeps the payload destination")
    }
```

#### 2. View-model end-to-end test
**File**: `CheckStitchTests/ChecklistImportExportViewModelTests.swift`
**Action**: modify

Add using the file's existing `makeStore(names:)` / `writeTempFile` helpers:

```swift
    @Test
    func importPreservesTheExportedDestination() throws {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let exported = try ChecklistExport.data(checklists: [
            Checklist(name: "Groceries", destinationListIdentifier: "list-a"),
        ])

        viewModel.importFile(at: try writeTempFile(exported))
        viewModel.commitImport()

        #expect(store.checklists.first?.destinationListIdentifier == "list-a")
    }
```

#### 3. Export-boundary regression test
**File**: `CheckStitchTests/ChecklistExportTests.swift`
**Action**: modify

Add, mirroring `testExportPreservesPriority`:

```swift
    /// Export → classify → decode keeps the chosen destination (codec v4 already
    /// encodes it; this pins the boundary).
    func testExportPreservesDestination() throws {
        let checklist = Checklist(name: "Groceries", destinationListIdentifier: "list-a")
        let data = try ChecklistExport.data(checklists: [checklist])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(env.checklists.first?.destinationListIdentifier, "list-a")
    }
```

### Verification
#### Automated
- [x] `make test-unit` passes (import-session, view-model, export suites)
- [x] `make build` passes with `WARNINGS_AS_ERRORS`

#### Manual
- [ ] Export a checklist with a chosen list, import it via the export/import sheet, and confirm the imported checklist's detail screen shows that list selected (when the list exists locally).

---

## Phase 3: Stale destination — preserve, fail closed at first run

Lock in the deferred-validation decision: an imported id that does not exist on
the target is kept (not reset), and running the checklist creates nothing and
reports `.destinationMissing`.

### Changes

#### 1. Stale-foreign-id integration test
**File**: `CheckStitchTests/ChecklistImportSessionTests.swift`
**Action**: modify

Add:

```swift
    /// A source-device destination id is usually absent on the target. Import
    /// must keep it (a re-created list could match later) and the run-path net
    /// must fail closed before creating anything.
    @Test
    func staleImportedDestinationFailsClosedAtFirstRun() async throws {
        let (session, store) = makeSession()
        let incoming = Checklist(name: "Groceries",
                                 items: [ChecklistItem(title: "Milk")],
                                 destinationListIdentifier: "list-deleted")
        _ = try session.stage(data: payload([incoming]))
        session.commit(selectedIDs: allIDs(session.candidates))

        let imported = try #require(store.checklists.first)
        #expect(imported.destinationListIdentifier == "list-deleted",
                "the id is preserved, not silently reset")

        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-a", title: "Reminders")],
            defaultIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: imported, targeting: spy)

        #expect(outcome == .destinationMissing)
        #expect(spy.createdTitles.isEmpty, "no reminders created for a stale destination")
    }
```

`SpyReminderDestination` and `ReminderListsSnapshot` are already available via
`TestFixtures.swift` and `CheckStitchCore`; no new fakes.

### Verification
#### Automated
- [x] `make test-unit` passes (new stale-destination case)
- [x] `make build` and `make build-mac` pass with `WARNINGS_AS_ERRORS`

#### Manual
- [ ] Import a checklist whose destination is unavailable on the device, run it, and confirm the "That list no longer exists; no reminders were created." message appears with no reminders added.

---

## Final gate (after all phases)

- [ ] `bash scripts/test.sh` prints `gate: ok` (simulator build → `make test` → `make build-mac` → `make watch-build` → shell tests → shellcheck)
- [ ] No codec/version/migration file changed; `duplicate()` untouched.