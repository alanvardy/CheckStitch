import CheckStitchCore
@testable import CheckStitch
import Foundation
import SwiftUI
import Testing

@MainActor
struct ChecklistImportExportViewModelTests {
    private func makeStore(names: [String]) -> ChecklistStore {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        for name in names { _ = store.create(name: name) }
        return store
    }

    /// Writes `data` to a unique temp file and returns its URL.
    private func writeTempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    @Test
    func exportFiltersBySelectionAndBuildsTheDocument() throws {
        let store = makeStore(names: ["Groceries", "Packing"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = [store.checklists[0].id]

        viewModel.exportSelected()

        #expect(viewModel.isExporting)
        #expect(viewModel.exportDocument != nil)
        #expect(!viewModel.isShowingExport)
    }

    @Test
    func emptySelectionExportsNothing() {
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)
        viewModel.beginExport()
        viewModel.exportSelection = []

        viewModel.exportSelected()

        #expect(viewModel.exportDocument == nil)
        #expect(!viewModel.isExporting)
    }

    @Test
    func readFailureReportsTheSystemMessage() {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")

        viewModel.importFile(at: missing)

        #expect(viewModel.importErrorMessage != nil)
        #expect(viewModel.importErrorMessage != "This file isn't a CheckStitch export.")
        #expect(!viewModel.isShowingImportSelection)
    }

    @Test
    func formatFailureReportsTheNotAnExportMessage() throws {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let url = try writeTempFile(Data("not json".utf8))

        viewModel.importFile(at: url)

        #expect(viewModel.importErrorMessage == "This file isn't a CheckStitch export.")
        #expect(!viewModel.isShowingImportSelection)
    }

    @Test
    func importFileStagesAndPresentsSelection() throws {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let url = try writeTempFile(try ChecklistExport.data(checklists: [
            Checklist(name: "A"),
            Checklist(name: "B"),
        ]))

        viewModel.importFile(at: url)

        #expect(viewModel.isShowingImportSelection)
        #expect(viewModel.importCandidates.map(\.checklist.name) == ["A", "B"])
        #expect(viewModel.importSelection == Set(viewModel.importCandidates.map(\.id)), "all ticked by default")
        #expect(store.checklists.isEmpty, "nothing written until commit")
    }

    @Test
    func commitImportAppliesTickSelection() throws {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let url = try writeTempFile(try ChecklistExport.data(checklists: [
            Checklist(name: "A"),
            Checklist(name: "B"),
        ]))

        viewModel.importFile(at: url)
        viewModel.importSelection = [viewModel.importCandidates[0].id]   // untick B
        viewModel.commitImport()

        #expect(store.checklists.map(\.name) == ["A"], "only the ticked checklist imports")
        #expect(!viewModel.isShowingImportSelection)
    }

    @Test
    func cancelImportDiscardsStagedFile() throws {
        let store = makeStore(names: [])
        let viewModel = ChecklistImportExportViewModel(store: store)
        let url = try writeTempFile(try ChecklistExport.data(checklists: [
            Checklist(name: "A"),
        ]))

        viewModel.importFile(at: url)
        viewModel.cancelImport()

        #expect(store.checklists.isEmpty, "cancel leaves the store untouched")
        #expect(viewModel.importCandidates.isEmpty)
        #expect(viewModel.importSelection.isEmpty)
        #expect(!viewModel.isShowingImportSelection)
    }

    @Test
    func emptySelectionCannotConfirm() {
        let empty = ChecklistSelectionView(
            title: "t", rows: [],
            selection: .constant([]),
            confirmTitle: "Import",
            onConfirm: {}, onCancel: {},
            rowAccessibilityID: "r", confirmAccessibilityID: "c")
        #expect(!empty.canConfirm, "no rows selected stays disabled")

        let one = ChecklistSelectionView(
            title: "t", rows: [ChecklistSelectionRow(id: UUID(), name: "A", detail: nil)],
            selection: .constant(Set([UUID()])),
            confirmTitle: "Import",
            onConfirm: {}, onCancel: {},
            rowAccessibilityID: "r", confirmAccessibilityID: "c")
        #expect(one.canConfirm)
    }

    @Test
    func conflictDecisionsAdvanceTheFIFOQueue() async throws {
        // Export two same-named checklists, import into a store that already has
        // that name → two conflicts, presented in file order.
        let exported = try ChecklistExport.data(checklists: [
            Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")]),
            Checklist(name: "Groceries", items: [ChecklistItem(title: "Eggs")]),
        ])
        let store = makeStore(names: ["Groceries"])
        let viewModel = ChecklistImportExportViewModel(store: store)

        viewModel.importFile(at: try writeTempFile(exported))
        viewModel.commitImport()   // populate the queue from the ticked (all) selection

        let first = viewModel.conflict
        #expect(first != nil)
        viewModel.decide(.keepExisting)
        // `advanceConflict` defers to the next main-actor turn.
        await Task.yield()
        #expect(viewModel.conflict != nil)
        #expect(viewModel.conflict?.id != first?.id)
        viewModel.decide(.keepBoth)
        await Task.yield()
        #expect(viewModel.conflict == nil)
    }
}
