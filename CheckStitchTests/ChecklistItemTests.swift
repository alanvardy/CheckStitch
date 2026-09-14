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
