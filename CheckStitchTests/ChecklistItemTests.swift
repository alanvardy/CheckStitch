@testable import CheckStitchCore
import Foundation
import Testing

struct ChecklistItemTests {
    @Test
    func checklistItemStableIdentityForDuplicateTitles() {
        let first = makeItem("one")
        let second = makeItem("one")
        #expect(first.id != second.id, "duplicate titles must not share identity")
        #expect(first == ChecklistItem(id: first.id, title: "one"))
    }

    @Test(arguments: ["", " ", "\t", "\n", "  \n "])
    func blankTitlesAreBlank(_ title: String) {
        #expect(ChecklistItem(title: title).isBlank)
    }

    @Test(arguments: ["x", " x ", "0"])
    func nonBlankTitlesAreNotBlank(_ title: String) {
        #expect(!ChecklistItem(title: title).isBlank)
    }

    @Test
    func codableRoundTripPreservesIdentity() throws {
        let item = ChecklistItem(title: "one")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ChecklistItem.self, from: data)
        #expect(decoded == item)
        #expect(decoded.id == item.id)
    }

    @Test(arguments: [nil, 0, 1, -3] as [Int?])
    func relativeDateRoundTripsThroughJSON(_ offset: Int?) throws {
        let item = ChecklistItem(title: "one", relativeDate: offset)
        let decoded = try JSONDecoder().decode(ChecklistItem.self, from: JSONEncoder().encode(item))
        #expect(decoded.relativeDate == offset)
        #expect(decoded == item)
    }

    /// A v2 item object: no `relativeDate` key anywhere.
    @Test
    func itemWithoutRelativeDateKeyDecodesToNil() throws {
        let id = UUID().uuidString
        let data = Data(#"{"id":"\#(id)","title":"one"}"#.utf8)
        let decoded = try JSONDecoder().decode(ChecklistItem.self, from: data)
        #expect(decoded.relativeDate == nil)
    }

    /// The encoder always writes the key, as JSON `null` when there is no date.
    @Test
    func encodeAlwaysEmitsRelativeDateKey() throws {
        let data = try JSONEncoder().encode(ChecklistItem(title: "one"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?.keys.contains("relativeDate") == true)
        #expect(object?["relativeDate"] is NSNull)
    }

    @Test
    func descriptionDefaultsToEmptyWhenKeyIsAbsent() throws {
        let id = UUID().uuidString
        let json = Data(#"{"id":"\#(id)","title":"Milk"}"#.utf8)
        let decoded = try JSONDecoder().decode(ChecklistItem.self, from: json)
        #expect(decoded.description == "")
        #expect(!decoded.hasDescription)
    }

    @Test
    func descriptionRoundTripsThroughCodable() throws {
        let item = ChecklistItem(title: "Milk", description: "2 litres, semi-skimmed")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ChecklistItem.self, from: data)
        #expect(decoded == item)
        #expect(decoded.description == "2 litres, semi-skimmed")
        #expect(decoded.hasDescription)
    }

    @Test(arguments: ["", " ", "\n"])
    func descriptionDoesNotUnblankAnEmptyTitle(_ description: String) {
        #expect(ChecklistItem(title: "  ", description: description).isBlank)
    }

    @Test(arguments: [" ", "\t", "\n", "  \n "])
    func whitespaceOnlyDescriptionReadsAsAbsent(_ description: String) {
        #expect(!ChecklistItem(title: "Milk", description: description).hasDescription)
    }

    @Test(arguments: ["x", " x "])
    func descriptionWithRealTextReadsAsPresent(_ description: String) {
        #expect(ChecklistItem(title: "Milk", description: description).hasDescription)
    }

    @Test
    func checklistDecodeDefaultsToDerivedOrder() throws {
        let first = UUID()
        let second = UUID()
        let json = Data(#"{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(first.uuidString)","title":"Milk"},{"id":"\#(second.uuidString)","title":"Eggs"}]}"#.utf8)

        let decoded = try JSONDecoder().decode(Checklist.self, from: json)
        #expect(decoded.itemOrder == [first, second])
        #expect(decoded.orderRevision == 0)
        #expect(decoded.orderModifiedAt == .distantPast)
    }

    @Test
    func normalizedOrderRepairsDrift() {
        let a = ChecklistItem(id: UUID(), title: "A")
        let b = ChecklistItem(id: UUID(), title: "B")
        let checklist = Checklist(items: [a, b], itemOrder: [b.id])

        let normalized = checklist.normalizedOrder()
        #expect(normalized.itemOrder == [b.id, a.id])
        #expect(normalized.items.map(\.id) == [b.id, a.id])
    }

    @Test
    func normalizedOrderDedupesDuplicateIds() {
        let id = UUID()
        let first = ChecklistItem(id: id, title: "First")
        let second = ChecklistItem(id: id, title: "Second")
        let checklist = Checklist(items: [first, second], itemOrder: [id, id])

        let normalized = checklist.normalizedOrder()
        #expect(normalized.itemOrder == [id])
        #expect(normalized.items.map(\.id) == [id])
        #expect(normalized.items.first?.title == "First", "the first occurrence is kept")
    }

    @Test
    func decodeWithDuplicateItemIdsIsTotal() throws {
        let id = UUID()
        let json = Data(#"{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(id.uuidString)","title":"Milk"},{"id":"\#(id.uuidString)","title":"Cheese"}]}"#.utf8)

        // Decode must not trap on a hand-corrupted payload; the duplicate is deduped.
        let decoded = try JSONDecoder().decode(Checklist.self, from: json)
        #expect(decoded.itemOrder == [id])
        #expect(decoded.items.map(\.title) == ["Milk"])
    }

    @Test
    func normalizedOrderAppendsMissingItem() {
        let a = ChecklistItem(id: UUID(), title: "A")
        let b = ChecklistItem(id: UUID(), title: "B")
        let c = ChecklistItem(id: UUID(), title: "C")
        let checklist = Checklist(items: [a, b, c], itemOrder: [a.id, c.id])

        let normalized = checklist.normalizedOrder()
        #expect(normalized.itemOrder == [a.id, c.id, b.id])
        #expect(normalized.items.map(\.id) == [a.id, c.id, b.id])
    }
}
