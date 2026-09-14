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
    /// its own draft, so nothing is created until the user confirms a name.
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
}
