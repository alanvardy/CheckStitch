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
        guard case .migratable(from: let version, envelope: let envelope) = outcome else {
            XCTFail("expected migratable outcome, got \(outcome)")
            return
        }
        XCTAssertEqual(version, 1)
        XCTAssertEqual(envelope.checklists.count, 1)
        XCTAssertEqual(envelope.checklists.first?.name, "Groceries")
        XCTAssertEqual(envelope.checklists.first?.items.first?.title, "Milk")
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
        guard case .migratable(from: let version, envelope: let envelope) = outcome else {
            XCTFail("expected migratable outcome, got \(outcome)")
            return
        }
        XCTAssertEqual(version, 2)
        XCTAssertEqual(envelope.checklists.count, 1)
        XCTAssertEqual(envelope.checklists.first?.name, "Groceries")
        XCTAssertEqual(envelope.checklists.first?.revision, 1)
        XCTAssertEqual(envelope.checklists.first?.items.first?.title, "Milk")
        XCTAssertEqual(envelope.checklists.first?.items.first?.revision, 1)
    }

    /// A v2 payload: it has sync state and tombstones, and must be accepted
    /// verbatim (never restamped) when classified.
    func testV2PayloadIsClassifiedMigratableWithTombstones() throws {
        let device = "device-a"
        let tombstone = ChecklistTombstone(
            checklistID: UUID(), itemID: nil, deletedAt: Date(timeIntervalSince1970: 42), revision: 3)
        let envelope = ChecklistEnvelope(
            version: 2, deviceID: device,
            checklists: [Checklist(name: "Groceries", modifiedAt: Date(timeIntervalSince1970: 7), revision: 5)],
            tombstones: [tombstone])

        XCTAssertEqual(ChecklistCodec.classify(try ChecklistCodec.encode(envelope)),
                       .migratable(from: 2, envelope: envelope))
    }

    func testCurrentVersionPayloadIsLoaded() throws {
        let envelope = ChecklistEnvelope(deviceID: "d", checklists: [Checklist(name: "x")])
        XCTAssertEqual(ChecklistCodec.classify(try ChecklistCodec.encode(envelope)), .loaded(envelope))
    }

    /// A v3 payload predates `relativeDate` but carries full sync and ordering
    /// state; it must classify as migratable and load verbatim.
    func testV3PayloadIsClassifiedMigratable() throws {
        let envelope = ChecklistEnvelope(
            version: 3, deviceID: "device-a",
            checklists: [Checklist(name: "Groceries", modifiedAt: Date(timeIntervalSince1970: 7), revision: 5)])

        XCTAssertEqual(ChecklistCodec.classify(try ChecklistCodec.encode(envelope)),
                       .migratable(from: 3, envelope: envelope))
    }

    func testFutureVersionIsUnsupported() {
        let data = Data(#"{"version":5,"checklists":[]}"#.utf8)
        XCTAssertEqual(ChecklistCodec.classify(data), .unsupportedVersion)
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

    /// A v2 payload written before the destination field existed: decodes as nil
    /// rather than throwing, so every checklist already stored keeps working.
    func testDecodesV2PayloadWithoutDestinationAsNil() {
        let id = UUID().uuidString
        let data = Data(#"{"version":2,"deviceID":"device-a","checklists":[{"id":"\#(id)","name":"Groceries","items":[],"modifiedAt":0,"revision":1}]}"#.utf8)

        let decoded = ChecklistCodec.decode(data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded.first?.destinationListIdentifier)
    }

    func testDestinationSurvivesEnvelopeRoundTrip() throws {
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")],
                                  destinationListIdentifier: "list-a")
        let envelope = ChecklistEnvelope(deviceID: "device-a", checklists: [checklist])

        let data = try ChecklistCodec.encode(envelope)

        XCTAssertEqual(ChecklistCodec.classify(data), .loaded(envelope))
        XCTAssertEqual(ChecklistCodec.decode(data).first?.destinationListIdentifier, "list-a")
    }

    /// A current-version (v4) envelope whose item carries no `description` key:
    /// must stay `.loaded` with an empty description (the additive-field
    /// guarantee). v3 payloads predate `relativeDate`, so they classify as
    /// `.migratable` instead — see `testV3PayloadIsClassifiedMigratable`.
    func testItemWithoutDescriptionClassifiesLoadedAsEmpty() throws {
        let itemID = UUID().uuidString
        let data = Data(#"{"version":4,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(itemID)","title":"Milk"}]}]}"#.utf8)

        guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(envelope.checklists.first?.items.first?.description, "")
    }

    func testDescriptionSurvivesEnvelopeRoundTrip() throws {
        let checklist = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", description: "2 litres")])
        let data = try ChecklistCodec.encode(ChecklistEnvelope(deviceID: "device-a", checklists: [checklist]))

        guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded, got \(ChecklistCodec.classify(data))")
            return
        }
        XCTAssertEqual(envelope.checklists.first?.items.first?.description, "2 litres")
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains(#""description""#) ?? false)
    }

    /// Sad path: a malformed (non-string) description throws, so the whole payload
    /// is `.unreadable` — only whole-key absence is tolerant.
    func testMalformedDescriptionMakesPayloadUnreadable() {
        let data = Data(#"{"version":4,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"x","items":[{"id":"\#(UUID().uuidString)","title":"Milk","description":42}]}]}"#.utf8)
        XCTAssertEqual(ChecklistCodec.classify(data), .unreadable)
    }

    func testFieldClocksSurviveEnvelopeRoundTrip() throws {
        let item = ChecklistItem(
            id: UUID(), title: "Milk", description: "2 litres",
            modifiedAt: Date(timeIntervalSince1970: 20), revision: 2,
            relativeDate: 3,
            titleRevision: 2, titleModifiedAt: Date(timeIntervalSince1970: 20),
            descriptionRevision: 3, descriptionModifiedAt: Date(timeIntervalSince1970: 30),
            relativeDateRevision: 4, relativeDateModifiedAt: Date(timeIntervalSince1970: 40))
        let envelope = ChecklistEnvelope(deviceID: "device-a", checklists: [
            Checklist(id: UUID(), name: "Groceries", items: [item],
                      modifiedAt: Date(timeIntervalSince1970: 10), revision: 1),
        ])

        let data = try ChecklistCodec.encode(envelope)

        XCTAssertEqual(ChecklistCodec.classify(data), .loaded(envelope))
        let decoded = try XCTUnwrap(ChecklistCodec.decode(data).first?.items.first)
        XCTAssertEqual(decoded.titleRevision, 2)
        XCTAssertEqual(decoded.titleModifiedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(decoded.descriptionRevision, 3)
        XCTAssertEqual(decoded.descriptionModifiedAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(decoded.relativeDateRevision, 4)
        XCTAssertEqual(decoded.relativeDateModifiedAt, Date(timeIntervalSince1970: 40))
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        for key in ["titleRevision", "titleModifiedAt", "descriptionRevision", "descriptionModifiedAt",
                    "relativeDateRevision", "relativeDateModifiedAt"] {
            XCTAssertTrue(raw.contains("\"\(key)\""), "the \(key) key is written unconditionally")
        }
    }

    /// A v4 payload whose item carries `revision`/`modifiedAt` but none of the
    /// six per-field clock keys: it must stay `.loaded` and seed every field
    /// clock from the item's coarse clock, matching pre-upgrade semantics.
    func testItemWithoutFieldClocksSeedsFromCoarseClock() throws {
        let data = Data(#"{"version":4,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk","revision":3,"modifiedAt":100}]}]}"#.utf8)

        guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
            XCTFail("expected loaded, got \(ChecklistCodec.classify(data))")
            return
        }
        let item = try XCTUnwrap(envelope.checklists.first?.items.first)
        XCTAssertEqual(item.titleRevision, 3)
        XCTAssertEqual(item.descriptionRevision, 3)
        XCTAssertEqual(item.relativeDateRevision, 3)
        XCTAssertEqual(item.titleModifiedAt, Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertEqual(item.descriptionModifiedAt, Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertEqual(item.relativeDateModifiedAt, Date(timeIntervalSinceReferenceDate: 100))
    }

    /// The new per-field keys ride the v4 envelope, so legacy classifications
    /// must not shift. Reuses the existing v1/v2/v3 literals as a lightweight guard.
    func testV1V2V3ClassificationUnchanged() {
        let v1 = Data(#"{"version":1,"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk"}]}]}"#.utf8)
        guard case .migratable(from: let v1From, envelope: _) = ChecklistCodec.classify(v1) else {
            XCTFail("expected v1 migratable outcome, got \(ChecklistCodec.classify(v1))")
            return
        }
        XCTAssertEqual(v1From, 1)

        let v2 = Data(#"{"version":2,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk","modifiedAt":100,"revision":1}]}]}"#.utf8)
        guard case .migratable(from: let v2From, envelope: _) = ChecklistCodec.classify(v2) else {
            XCTFail("expected v2 migratable outcome, got \(ChecklistCodec.classify(v2))")
            return
        }
        XCTAssertEqual(v2From, 2)

        let v3 = Data(#"{"version":3,"deviceID":"device-a","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk","modifiedAt":100,"revision":1}]}]}"#.utf8)
        guard case .migratable(from: let v3From, envelope: _) = ChecklistCodec.classify(v3) else {
            XCTFail("expected v3 migratable outcome, got \(ChecklistCodec.classify(v3))")
            return
        }
        XCTAssertEqual(v3From, 3)
    }
}
