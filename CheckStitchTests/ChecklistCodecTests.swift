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
            ], orderRevision: 4, orderModifiedAt: Date(timeIntervalSince1970: 1_000)),
            Checklist(name: "Chores"),
        ]
        let envelope = ChecklistEnvelope(deviceID: "device-a", checklists: checklists)

        let data = try ChecklistCodec.encode(envelope)

        XCTAssertEqual(ChecklistCodec.classify(data), .loaded(envelope))
        XCTAssertEqual(ChecklistCodec.decode(data), checklists)
        // v3 payloads carry the order keys, and the order stamp survives a round trip.
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains(#""itemOrder""#) ?? false)
        XCTAssertEqual(ChecklistCodec.decode(data).first?.orderRevision, 4)
        XCTAssertEqual(ChecklistCodec.decode(data).first?.orderModifiedAt, Date(timeIntervalSince1970: 1_000))
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

    /// A true v2 payload: version 2 with deviceID/tombstones and sync-stamped
    /// records, but none of the v3 order keys.
    func testV2PayloadIsClassifiedMigratable() {
        let v2 = Data(#"{"version":2,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","modifiedAt":1700000000,"revision":1,"items":[{"id":"\#(UUID().uuidString)","title":"Milk","modifiedAt":1700000000,"revision":1}]}]}"#.utf8)

        let outcome = ChecklistCodec.classify(v2)
        guard case .migratable(from: let version, checklists: let checklists) = outcome else {
            XCTFail("expected migratable outcome, got \(outcome)")
            return
        }
        XCTAssertEqual(version, 2)
        XCTAssertEqual(checklists.count, 1)
        XCTAssertEqual(checklists.first?.name, "Groceries")
        XCTAssertEqual(checklists.first?.revision, 1)
        XCTAssertEqual(checklists.first?.items.first?.title, "Milk")
        XCTAssertEqual(checklists.first?.items.first?.revision, 1)
    }

    func testV3RoundTripPreservesOrder() throws {
        let first = ChecklistItem(id: UUID(), title: "First")
        let second = ChecklistItem(id: UUID(), title: "Second")
        let envelope = ChecklistEnvelope(deviceID: "device-a", checklists: [
            Checklist(name: "Ordered", items: [first, second], itemOrder: [second.id, first.id], orderRevision: 2),
        ])

        let data = try ChecklistCodec.encode(envelope)
        guard case .loaded(let decoded) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded outcome, got \(ChecklistCodec.classify(data))")
            return
        }
        let decodedChecklist = try XCTUnwrap(decoded.checklists.first)
        XCTAssertEqual(decodedChecklist.itemOrder, [second.id, first.id])
        XCTAssertEqual(decodedChecklist.items.map(\.id), [second.id, first.id])
        XCTAssertEqual(decodedChecklist.orderRevision, 2)
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
