import CheckStitchCore
@testable import CheckStitch
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
}