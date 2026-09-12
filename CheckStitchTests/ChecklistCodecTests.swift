import XCTest
@testable import CheckStitch
import CheckStitchCore

@MainActor
final class ChecklistCodecTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let checklists = [
            Checklist(name: "Groceries", items: [
                ChecklistItem(title: "Milk"),
                ChecklistItem(title: "Eggs"),
            ]),
            Checklist(name: "Chores"),
        ]
        let envelope = ChecklistEnvelope(deviceID: "device-a", checklists: checklists)

        let data = try ChecklistCodec.encode(envelope)

        XCTAssertEqual(ChecklistCodec.classify(data), .loaded(envelope))
        XCTAssertEqual(ChecklistCodec.decode(data), checklists)
    }

    /// A true v1 payload: no `deviceID`, `tombstones`, `modifiedAt`, or
    /// `revision` keys anywhere — exactly what the old encoder wrote.
    func testLegacyV1PayloadIsClassifiedMigratable() {
        let legacy = Data(#"{"version":1,"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk"}]}]}"#.utf8)

        let outcome = ChecklistCodec.classify(legacy)
        guard case .migratable(from: let version, checklists: let checklists) = outcome else {
            XCTFail("expected migratable outcome, got \(outcome)")
            return
        }
        XCTAssertEqual(version, 1)
        XCTAssertEqual(checklists.count, 1)
        XCTAssertEqual(checklists.first?.name, "Groceries")
        XCTAssertEqual(checklists.first?.items.first?.title, "Milk")
    }

    func testUnknownVersionDecodesAsEmpty() {
        let data = Data(#"{"version":99,"checklists":[{"id":"\#(UUID().uuidString)","name":"x","items":[]}]}"#.utf8)

        XCTAssertEqual(ChecklistCodec.decode(data), [])
    }

    func testEmptyEnvelopeDecodes() throws {
        XCTAssertEqual(ChecklistCodec.decode(try ChecklistCodec.encode(ChecklistEnvelope(deviceID: "", checklists: []))), [])
    }

    func testClassifyDistinguishesUnsupportedFromUnreadable() {
        XCTAssertEqual(ChecklistCodec.classify(Data("not json".utf8)), .unreadable)

        let newer = Data(#"{"version":99,"checklists":[]}"#.utf8)
        XCTAssertEqual(ChecklistCodec.classify(newer), .unsupportedVersion)
    }

    func testV1PayloadWithoutIsBlankStillDecodes() {
        let id = UUID().uuidString
        let data = Data(#"{"version":1,"checklists":[{"id":"\#(UUID().uuidString)","name":"x","items":[{"id":"\#(id)","title":"Milk"}]}]}"#.utf8)

        let decoded = ChecklistCodec.decode(data)
        XCTAssertEqual(decoded.first?.items.first?.title, "Milk")
        XCTAssertFalse(decoded.first?.items.first?.isBlank ?? true)
    }
}