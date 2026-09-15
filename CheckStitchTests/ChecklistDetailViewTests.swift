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

    /// The Items rows render each item's description read-only; this stages a
    /// real render pass against an injected store (the row's fields are private
    /// to the view graph, so their commit behaviour is pinned by the store tests).
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

    /// An absent date renders blank: "no date" is the absence of a phrase, not a
    /// placeholder like "0".
    @Test
    func missingDateRendersAsBlank() {
        #expect(DueDateLabel.text(for: nil).isEmpty)
    }

    /// Every offset spells out to its own non-empty phrase, so no two offsets
    /// collapse onto the same label.
    @Test(arguments: [0, 1, -1, 3, -3, 12] as [Int])
    func everyOffsetRendersItsOwnPhrase(_ offset: Int) {
        let label = DueDateLabel.text(for: offset)
        #expect(!label.isEmpty)
        #expect(label != DueDateLabel.text(for: offset + 2))
    }

    /// The day count survives into the phrase, so "in 3 days" cannot silently
    /// become "in 0 days".
    @Test
    func futureAndPastPhrasesCarryTheirDayCount() {
        #expect(DueDateLabel.text(for: 3).contains("3"))
        #expect(DueDateLabel.text(for: -3).contains("3"))
    }

    /// The menu's offsets: today, tomorrow and three days out, each spelled out.
    @Test
    func presetsSpellOutTodayTomorrowAndThreeDaysOut() {
        #expect(DueDateLabel.presets == [0, 1, 3])
        #expect(DueDateLabel.presets.allSatisfy { !DueDateLabel.text(for: $0).isEmpty })
    }

    /// The row renders the description and date it is given, through the
    /// `DueDateLabel` seam rather than a typed field.
    @Test
    func itemRowRendersItsDescriptionAndDate() {
        let row = ItemRow(
            checklistID: UUID(), itemID: UUID(), title: "Milk",
            description: "2 litres", relativeDate: 3)
        #if os(macOS)
        #expect(ImageRenderer(content: row).nsImage != nil)
        #else
        #expect(ImageRenderer(content: row).uiImage != nil)
        #endif
    }

    /// A cleared title falls back to the placeholder rather than leaving the row
    /// rendering blank.
    @Test
    func blankTitlesFallBackToTheItemPlaceholder() {
        #expect(!ItemRow.displayTitle("").isEmpty)
        #expect(ItemRow.displayTitle("Milk") == "Milk")
    }

    /// The row carries the checklist identity its pushed edit link needs.
    @Test
    func itemRowCarriesItsChecklistForTheEditLink() {
        let described = String(describing: ItemRow(
            checklistID: UUID(), itemID: UUID(), title: "Milk",
            description: "2 litres", relativeDate: 1))
        #expect(described.contains("checklistID"))
        #expect(described.contains("itemID"))
        #expect(described.contains("relativeDate"))
    }

    /// The edit screen renders against an injected store for an existing item.
    @Test
    func itemEditViewRendersForAnExistingItem() throws {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let checklist = store.create(name: "Groceries")
        store.addItem(to: checklist.id)
        let itemID = try #require(store.checklist(id: checklist.id)?.items.first?.id)
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
