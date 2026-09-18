import CheckStitchCore
@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct ChecklistListViewModelTests {
    private func makeViewModel() -> ChecklistListViewModel {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        return ChecklistListViewModel(store: store)
    }

    @Test
    func createChecklistReturnsTheNewID() {
        let viewModel = makeViewModel()
        let id = viewModel.createChecklist()
        #expect(viewModel.checklists.count == 1)
        #expect(viewModel.checklists.first?.id == id)
    }

    @Test
    func createChecklistDisambiguatesDuplicateNames() {
        let viewModel = makeViewModel()
        _ = viewModel.createChecklist()
        _ = viewModel.createChecklist()
        #expect(viewModel.checklists.map(\.name) == ["New checklist", "New checklist 2"])
    }

    @Test
    func removeChecklistRemovesIt() {
        let viewModel = makeViewModel()
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.removeChecklist(id: first)
        #expect(viewModel.checklists.map(\.id) == [second])
    }

    @Test
    func moveChecklistUpReorders() {
        let viewModel = makeViewModel()
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: second, up: true)
        #expect(viewModel.checklists.map(\.id) == [second, first])
    }

    @Test
    func moveChecklistDownReorders() {
        let viewModel = makeViewModel()
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: first, up: false)
        #expect(viewModel.checklists.map(\.id) == [second, first])
    }

    @Test
    func unknownIDIsANoOp() {
        let viewModel = makeViewModel()
        let only = viewModel.createChecklist()
        viewModel.removeChecklist(id: UUID())
        viewModel.moveChecklist(id: UUID(), up: true)
        #expect(viewModel.checklists.map(\.id) == [only])
    }
}
