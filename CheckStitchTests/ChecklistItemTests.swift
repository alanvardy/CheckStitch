@testable import CheckStitchCore
import Testing

struct ChecklistItemTests {
    @Test
    func checklistItemStableIdentityForDuplicateTitles() {
        let first = makeItem("one")
        let second = makeItem("one")
        #expect(first.id != second.id, "duplicate titles must not share identity")
        #expect(first == ChecklistItem(id: first.id, title: "one"))
    }
}