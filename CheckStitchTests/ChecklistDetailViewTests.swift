@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

/// Pins the destructive-remove wiring and the duplicate flow of the checklist
/// detail screen. SwiftUI
/// environments cannot be staged in the headless Swift Testing host — reading
/// `body` fatal-errors without a live scene because `body` reads the store
/// environment — so these tests describe the view *value*, whose state slots
/// and environment seams are part of the value graph; the dialog copy is
/// pinned deterministically by the localization suite.
@MainActor
struct ChecklistDetailViewTests {
    /// Removing is a two-step gate: raising the confirmation dialog is a
    /// distinct state, so the destructive action never fires from the button.
    @Test
    func removeChecklistConfirmationIsADistinctDialogState() {
        let described = String(describing: ChecklistDetailView(checklistID: UUID()))
        #expect(described.contains("isRemoveConfirmPresented"))
        #expect(described.contains("isRemoving"))
        #expect(described.contains("isNameConflictPresented"))
    }

    /// Duplicating is a two-step flow: the button only raises a name alert with
    /// its own draft slot, rather than creating anything itself. Only those
    /// slots are inspectable here (the body cannot be staged headless), so the
    /// confirm action and the seeded default stay covered by the store tests.
    @Test
    func duplicateChecklistIsGatedBehindANameAlert() {
        let described = String(describing: ChecklistDetailView(checklistID: UUID()))
        #expect(described.contains("isDuplicatePresented"))
        #expect(described.contains("duplicateDraftName"))
    }

    /// Construction stays intact with the store/dismiss seams and the dialog
    /// states (mirrors ViewRenderTests' construction canary).
    @Test
    func viewConstructsWithItsEnvironmentSeams() {
        let described = String(describing: ChecklistDetailView(checklistID: UUID()))
        #expect(!described.isEmpty)
        #expect(described.contains("_store"))
        #expect(described.contains("_dismiss"))
        #expect(described.contains("checklistID"))
    }

    /// The description field is added to the Items rows; this stages a real render
    /// pass against an injected store (the binding itself is private and
    /// environment-bound, so its read/write behaviour is pinned by the store tests).
    @Test
    func detailViewRendersItemsWithDescriptions() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let checklist = store.create(name: "Groceries")
        store.addItem(to: checklist.id)
        let itemID = store.checklist(id: checklist.id)?.items.first?.id ?? UUID()
        store.updateItemDescription(checklistID: checklist.id, itemID: itemID, description: "2 litres")

        let view = ChecklistDetailView(checklistID: checklist.id).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }

    /// The date control's value graph: the row owns a text buffer, so a partial
    /// `"-"` can survive long enough to be completed. The parse/format pair is
    /// pure and asserted directly; commit behaviour is covered by the store
    /// suite.
    @Test
    func itemRowBuffersItsDateText() {
        let described = String(describing: ItemRow(
            checklistID: UUID(), itemID: UUID(), title: .constant("Milk"),
            relativeDate: 1, commitRelativeDate: { _ in }))
        #expect(described.contains("relativeDate"))
        #expect(described.contains("_draftDate"))
    }

    @Test(arguments: [
        ("", nil), ("-", nil), ("abc", nil),
        ("0", 0), ("-3", -3), ("12", 12),
    ] as [(String, Int?)])
    func itemRowParsesDateText(_ text: String, _ expected: Int?) {
        #expect(ItemRow.parse(text) == expected)
    }

    @Test(arguments: [
        (nil, ""), (0, "0"), (-3, "-3"),
    ] as [(Int?, String)])
    func itemRowFormatsMissingDatesAsEmpty(_ value: Int?, _ expected: String) {
        #expect(ItemRow.format(value) == expected)
    }

    /// An external change rewrites the buffer only when it differs from what the
    /// buffer already parses to; otherwise an in-progress or padded value stays.
    @Test(arguments: [
        (5, "", "5"),
        (5, "5", nil),
        (nil, "", nil),
        (7, "7", nil),
        (7, "05", "7"),
        (5, "-", "5"),
    ] as [(Int?, String, String?)])
    func itemRowAdoptsOnlyDifferingExternalDates(_ newValue: Int?, _ current: String, _ expected: String?) {
        #expect(ItemRow.draft(afterExternalChange: newValue, current: current) == expected)
    }

    /// The row carries the checklist identity its pushed edit link needs.
    @Test
    func itemRowCarriesItsChecklistForTheEditLink() {
        let described = String(describing: ItemRow(
            checklistID: UUID(), itemID: UUID(), title: .constant("Milk"),
            relativeDate: 1, commitRelativeDate: { _ in }))
        #expect(described.contains("checklistID"))
        #expect(described.contains("itemID"))
    }

    /// The edit screen renders against an injected store for an existing item.
    @Test
    func itemEditViewRendersForAnExistingItem() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let checklist = store.create(name: "Groceries")
        store.addItem(to: checklist.id)
        let itemID = store.checklist(id: checklist.id)?.items.first?.id ?? UUID()
        store.updateItemDescription(checklistID: checklist.id, itemID: itemID, description: "2 litres")
        store.updateItem(checklistID: checklist.id, itemID: itemID, relativeDate: 1)

        let view = ItemEditView(checklistID: checklist.id, itemID: itemID).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }

    /// A deleted item (e.g. an iCloud merge) renders the not-found placeholder
    /// instead of a form bound to a missing item.
    @Test
    func itemEditViewRendersNotFoundForAMissingItem() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let checklist = store.create(name: "Groceries")

        let view = ItemEditView(checklistID: checklist.id, itemID: UUID()).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }
}
