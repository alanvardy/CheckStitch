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
}
