@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

/// Pins the export sheet's pure selection logic and its renderability against
/// an injected store. The store arrives through an environment seam (the same
/// `.environment(store)` dance `ChecklistDetailViewTests` uses), so the render
/// helper stages a real pass against it.
@MainActor
struct ExportChecklistsViewTests {
    @Test
    func exportViewRendersAndDerivesCanExportFromSelection() {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let checklist = store.create(name: "Groceries")

        let empty = ExportChecklistsView(selection: .constant([]), onExport: {}, onShare: {})
        let filled = ExportChecklistsView(selection: .constant(Set([checklist.id])),
                                          onExport: {}, onShare: {})

        #expect(empty.canExport == false, "an empty selection must disable Export")
        #expect(filled.canExport == true, "a non-empty selection must enable Export")
        #expect(renders(empty.environment(store)))
        #expect(renders(filled.environment(store)))
    }

    @Test
    func toggledAddsAndRemovesSelection() {
        let id = UUID()
        #expect(ExportChecklistsView.toggled([], id: id) == Set([id]))
        #expect(ExportChecklistsView.toggled(Set([id]), id: id) == Set<UUID>())
    }

    @Test
    func selectAllReturnsEveryActiveChecklist() {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let a = store.create(name: "Groceries")
        let b = store.create(name: "Home")

        #expect(ExportChecklistsView.selectAll(store.activeChecklists) == Set([a.id, b.id]))
    }

    @Test
    func exportSheetWithSelectAllStillRenders() {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let view = ExportChecklistsView(selection: .constant([]), onExport: {}, onShare: {})

        #expect(renders(view.environment(store)))
    }

    /// The import caller omits the optional select-all fields; when unset they
    /// must be inert, so the shared sheet still renders exactly as before.
    @Test
    func sharedSheetWithoutSelectAllFieldsStillRenders() {
        let view = ChecklistSelectionView(
            title: "Import Checklists",
            rows: [ChecklistSelectionRow(id: UUID(), name: "Groceries", detail: nil)],
            selection: .constant([]),
            confirmTitle: "Import",
            onConfirm: {},
            onCancel: {},
            rowAccessibilityID: "importSelectionRow",
            confirmAccessibilityID: "confirmImportButton")

        #expect(renders(view))
    }

    /// Renders `view` offscreen and reports whether a frame was produced.
    private func renders(_ view: some View) -> Bool {
        #if os(macOS)
        return ImageRenderer(content: view).nsImage != nil
        #else
        return ImageRenderer(content: view).uiImage != nil
        #endif
    }
}