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
        let data = try ChecklistExport.data(checklists: selected)

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

    func testExportEmptySelectionClassifiesLoadedWithNoChecklists() throws {
        let data = try ChecklistExport.data(checklists: [])

        guard case .loaded(let env) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertTrue(env.checklists.isEmpty)
    }

    func testFilenameIsStableForFixedDate() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 2026-09-14 12:00 UTC
        let date = Date(timeIntervalSince1970: 1_789_387_200)

        XCTAssertEqual(ChecklistExport.filename(for: date, calendar: utc), "CheckStitch-2026-09-14")
    }

    func testFileWrapperCarriesEncodedBytes() throws {
        // One captured selection feeds both sides: two fresh `selectedPair()`
        // calls would mint different UUIDs and the bytes could never match.
        let selected = selectedPair()
        let doc = try ChecklistExportDocument(checklists: selected)
        // `fileWrapper` returns exactly the bytes held in `data` (the framework
        // supplies its own `WriteConfiguration` — that type has no accessible
        // initializers, so the writer is exercised through the same value).
        let contents = doc.data
        let expected = try ChecklistExport.data(checklists: selected)

        XCTAssertEqual(contents, expected)
        guard case .loaded(_) = ChecklistCodec.classify(contents) else {
            XCTFail("wrapper bytes did not classify as loaded, got \(ChecklistCodec.classify(contents))")
            return
        }
    }
}