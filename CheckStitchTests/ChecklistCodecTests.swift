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

        let data = try ChecklistCodec.encode(checklists)

        XCTAssertEqual(ChecklistCodec.decode(data), checklists)
    }

    func testUnknownVersionDecodesAsEmpty() {
        let data = Data(#"{"version":99,"checklists":[{"id":"\#(UUID().uuidString)","name":"x","items":[]}]}"#.utf8)

        XCTAssertEqual(ChecklistCodec.decode(data), [])
    }

    func testEmptyEnvelopeDecodes() throws {
        XCTAssertEqual(ChecklistCodec.decode(try ChecklistCodec.encode([])), [])
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