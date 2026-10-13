@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

/// Render and construction coverage for the pushed Checklist Options screen.
/// `String(describing:)` cannot see body identifiers, so `ImageRenderer` is the
/// body oracle, exactly as `ViewRenderTests` uses it.
@MainActor
struct ChecklistOptionsViewTests {
    /// Happy path: the screen renders for an existing checklist against an
    /// injected store.
    @Test
    func optionsViewRendersForAnExistingChecklist() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let checklist = store.create(name: "Groceries")

        let view = ChecklistOptionsView(checklistID: checklist.id).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }

    /// Sad path: a checklist deleted elsewhere (e.g. an iCloud merge) renders
    /// the not-found placeholder instead of a form bound to a missing value.
    @Test
    func optionsViewRendersNotFoundForAMissingChecklist() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)

        let view = ChecklistOptionsView(checklistID: UUID()).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }

    /// Carries the store seam plus the Destination state it moved off the edit
    /// screen (the destination-picker note and list snapshot live here now).
    @Test
    func optionsViewCarriesItsMovedStateSeams() {
        let described = String(describing: ChecklistOptionsView(checklistID: UUID()))
        #expect(described.contains("_store"))
        #expect(described.contains("checklistID"))
        #expect(described.contains("listsSnapshot"))
        #expect(described.contains("destinationUnavailable"))
    }
}
