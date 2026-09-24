@testable import CheckStitch
import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ContentViewSettingsActionTests {
    @Test
    func routeMapsExport() {
        #expect(SettingsDataActionRoute(.export) == .export)
    }

    @Test
    func routeMapsImportChecklists() {
        #expect(SettingsDataActionRoute(.importChecklists) == .importChecklists)
    }

    @Test
    func stagedActionSurvivesTakeAndRoutes() throws {
        let viewModel = SettingsViewModel()
        viewModel.stage(.importChecklists)
        let taken = try #require(viewModel.takeStaged())
        #expect(SettingsDataActionRoute(taken) == .importChecklists)
        // Sad path: the queue hands the action over exactly once.
        #expect(viewModel.takeStaged() == nil)
    }

    /// Recon gap: `ChecklistListViewModelTests` has up/down reorders but no
    /// first/last boundary cases. `ChecklistStore.moved` returns `nil` out of
    /// range, so these must be no-ops.
    @Test
    func moveChecklistFirstUpIsANoOp() {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let viewModel = ChecklistListViewModel(store: store)
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: first, up: true)
        #expect(viewModel.checklists.map(\.id) == [first, second])
    }

    @Test
    func moveChecklistLastDownIsANoOp() {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let viewModel = ChecklistListViewModel(store: store)
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: second, up: false)
        #expect(viewModel.checklists.map(\.id) == [first, second])
    }
}
