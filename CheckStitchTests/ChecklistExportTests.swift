import XCTest
@testable import CheckStitch
import CheckStitchCore

@MainActor
final class ChecklistExportTests: XCTestCase {
    private func makeChecklists() -> [Checklist] {
        [Checklist(name: "Groceries", items: [
            ChecklistItem(title: "Milk", description: "2%", relativeDate: 1),
            ChecklistItem(title: "Eggs"),
        ]),
        Checklist(name: "Packing", items: [ChecklistItem(title: "Socks")]),
        Checklist(name: "Third", items: [ChecklistItem(title: "Unused")])]
    }

    /// Two of the three fixture checklists — the "selected subset" every
    /// export test starts from.
    private func selectedPair() -> [Checklist] {
        let all = makeChecklists()
        return [all[0], all[1]]
    }

    func testExportOfSubsetRoundTripsThroughCodec() throws {
        let selected = selectedPair()
        let data = try ChecklistExport.data(checklists: selected, from: [])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(env.checklists, selected)
        XCTAssertEqual(env.checklists.map(\.name), ["Groceries", "Packing"])
        guard let groceries = env.checklists.first else {
            XCTFail("export lost the Groceries checklist")
            return
        }
        XCTAssertEqual(groceries.items.map(\.title), ["Milk", "Eggs"])
        XCTAssertEqual(groceries.items.map(\.id), groceries.itemOrder)
        XCTAssertEqual(groceries.items.first?.description, "2%")
        XCTAssertEqual(groceries.items.first?.relativeDate, 1)
        XCTAssertEqual(env.deviceID, "")
        XCTAssertTrue(env.tombstones.isEmpty)
    }

    /// A `.high` item exported, classified back `.loaded`, and decoded keeps its
    /// priority and its priority clock riding the coarse revision.
    func testExportPreservesPriority() throws {
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", priority: .high)])
        let data = try ChecklistExport.data(checklists: [checklist], from: [])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(env.checklists, [checklist])
        guard let item = env.checklists.first?.items.first else {
            XCTFail("export lost the item")
            return
        }
        XCTAssertEqual(item.priority, ChecklistItemPriority.high)
        XCTAssertEqual(item.priorityRevision, item.revision)
    }

    /// A checklist containing a disabled item exports and imports with the flag
    /// (and its per-field clock) intact.
    func testExportPreservesDisabledItem() throws {
        let checklist = Checklist(name: "Groceries", items: [
            ChecklistItem(title: "Milk", isEnabled: true),
            ChecklistItem(title: "Eggs", isEnabled: false),
        ])
        let data = try ChecklistExport.data(checklists: [checklist], from: [])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(env.checklists, [checklist])
        XCTAssertEqual(env.checklists.first?.items.map(\.isEnabled), [true, false])
        guard let eggs = env.checklists.first?.items.last else {
            XCTFail("export lost the disabled item")
            return
        }
        XCTAssertFalse(eggs.isEnabled)
        XCTAssertEqual(eggs.enabledRevision, eggs.revision)
    }

    /// Export → classify → decode keeps the chosen destination (codec v4 already
    /// encodes it; this pins the boundary).
    func testExportPreservesDestination() throws {
        let checklist = Checklist(name: "Groceries", destinationListIdentifier: "list-a")
        let data = try ChecklistExport.data(checklists: [checklist], from: [])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(env.checklists.first?.destinationListIdentifier, "list-a")
    }

    /// Export → classify → decode keeps the template multiple.
    func testExportPreservesMultiple() throws {
        let checklist = Checklist(name: "Groceries", multiple: 7)
        let data = try ChecklistExport.data(checklists: [checklist], from: [])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(env.checklists.first?.multiple, 7)
    }

    /// A hand-constructed out-of-range payload is clamped into `multipleRange`
    /// at decode, so an exported/imported payload can never carry an invalid
    /// factor off the wire.
    func testExportClampsOutOfRangeMultipleOnDecode() throws {
        for (raw, expected) in [(0, 1), (100, 99)] {
            let checklist = Checklist(name: "Groceries", multiple: raw)
            let data = try ChecklistExport.data(checklists: [checklist], from: [])

            guard case .loaded(let env) = ChecklistCodec.classify(data) else {
                XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
                return
            }
            XCTAssertEqual(env.checklists.first?.multiple, expected,
                           "\(raw) clamps to \(expected) on decode")
        }
    }

    func testExportEmptySelectionClassifiesLoadedWithNoChecklists() throws {
        let data = try ChecklistExport.data(checklists: [], from: [])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertTrue(env.checklists.isEmpty)
    }

    func testFilenameDefaultPathProducesDatedStem() {
        // Exercises the `.now`/`.current` defaults: assert the shape rather than
        // a fixed date, so the test cannot break across a day boundary.
        let stem = ChecklistExport.filename()
        XCTAssertNotNil(stem.range(of: #"^CheckStitch-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression),
                        "unexpected default filename stem: \(stem)")
    }

    func testFilenameIsStableForFixedDate() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 2026-09-14 12:00 UTC
        let date = Date(timeIntervalSince1970: 1_789_387_200)

        XCTAssertEqual(ChecklistExport.filename(for: date, calendar: utc), "CheckStitch-2026-09-14")
    }

    func testFileWrapperCarriesEncodedBytes() throws {
        let selected = selectedPair()
        let doc = try ChecklistExportDocument(checklists: selected, from: [])
        let contents = doc.data

        // Assert semantically rather than byte-for-byte: `fileWrapper` returns
        // exactly `data`, but independent `JSONEncoder` encodes of the same
        // value are NOT guaranteed byte-identical (key order may vary across
        // encodes), so comparing two raw byte arrays is inherently flaky. Decode
        // the document's bytes and compare the envelope instead.
        guard case .loaded(let env) = ChecklistCodec.classify(contents) else {
            XCTFail("wrapper bytes did not classify as loaded, got \(ChecklistCodec.classify(contents))")
            return
        }
        XCTAssertEqual(env.checklists, selected)
        XCTAssertEqual(env.deviceID, "")
        XCTAssertTrue(env.tombstones.isEmpty)
    }

    /// The referenced folder rides along (deduped by id); unreferenced folders are
    /// dropped, and the export ships no tombstones and no device identity.
    func testExportCarriesReferencedFoldersDedupedAndShipsNoTombstones() throws {
        let groceries = Folder(name: "Groceries")
        let folders: [Folder] = [groceries, Folder(name: "Unreferenced")]
        let a = Checklist(name: "A", folderID: groceries.id)
        let b = Checklist(name: "B", folderID: groceries.id)
        let loose = Checklist(name: "Loose")

        let data = try ChecklistExport.data(checklists: [a, b, loose], from: folders)

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(env.folders.map(\.name), ["Groceries"])
        XCTAssertTrue(env.folderTombstones.isEmpty)
        XCTAssertTrue(env.tombstones.isEmpty)
        XCTAssertEqual(env.deviceID, "")
    }

    /// A selection with no folder membership exports no folders.
    func testExportOmitsFoldersWhenSelectionHasNone() throws {
        let data = try ChecklistExport.data(checklists: [Checklist(name: "Loose")],
                                            from: [Folder(name: "Unreferenced")])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertTrue(env.folders.isEmpty)
    }

    /// Regression pin for the export trio: a one-folder export carries exactly
    /// that folder and ships no tombstones and no device identity. Deliberately
    /// does not re-assert dedup (that lives in
    /// `testExportCarriesReferencedFoldersDedupedAndShipsNoTombstones`).
    func testExportFolderInvariants() throws {
        let groceries = Folder(name: "Groceries")
        let member = Checklist(name: "Groceries", folderID: groceries.id)
        let data = try ChecklistExport.data(checklists: [member], from: [groceries])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(env.folders.count, 1)
        XCTAssertEqual(env.folders.first?.name, "Groceries")
        XCTAssertTrue(env.folderTombstones.isEmpty)
        XCTAssertTrue(env.tombstones.isEmpty)
        XCTAssertEqual(env.deviceID, "")
    }
}