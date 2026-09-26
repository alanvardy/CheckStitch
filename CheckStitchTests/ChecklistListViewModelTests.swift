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

    @Test
    func folderSectionsGroupMembers() {
        let viewModel = makeViewModel()
        let folderA = viewModel.createFolder(name: "Work")
        let folderB = viewModel.createFolder(name: "Personal")
        let c1 = viewModel.createChecklist()
        let c2 = viewModel.createChecklist()
        let c3 = viewModel.createChecklist()
        viewModel.moveChecklist(id: c1, toFolder: folderA)
        viewModel.moveChecklist(id: c2, toFolder: folderB)

        let a = viewModel.folders.first { $0.id == folderA }!
        let b = viewModel.folders.first { $0.id == folderB }!
        #expect(viewModel.checklists(in: a).map(\.id) == [c1])
        #expect(viewModel.checklists(in: b).map(\.id) == [c2])
        #expect(viewModel.checklists(in: nil).map(\.id) == [c3])
    }

    @Test
    func looseListKeepsGlobalOrder() {
        let viewModel = makeViewModel()
        let folder = viewModel.createFolder(name: "Work")
        let c1 = viewModel.createChecklist()
        let c2 = viewModel.createChecklist()
        let c3 = viewModel.createChecklist()
        viewModel.moveChecklist(id: c2, toFolder: folder)

        // Loose members (c1, c3) retain their creation order.
        #expect(viewModel.checklists(in: nil).map(\.id) == [c1, c3])
    }

    @Test
    func moveToFolderUpdatesGrouping() {
        let viewModel = makeViewModel()
        let folder = viewModel.createFolder(name: "Work")
        let checklist = viewModel.createChecklist()
        #expect(viewModel.checklists(in: nil).map(\.id) == [checklist])

        viewModel.moveChecklist(id: checklist, toFolder: folder)

        let f = viewModel.folders.first { $0.id == folder }!
        #expect(viewModel.checklists(in: nil).map(\.id) == [])
        #expect(viewModel.checklists(in: f).map(\.id) == [checklist])
    }

    @Test
    func moveToUnknownFolderLeavesMembershipUnchanged() {
        let viewModel = makeViewModel()
        let checklist = viewModel.createChecklist()
        viewModel.moveChecklist(id: checklist, toFolder: UUID())
        #expect(viewModel.checklists(in: nil).map(\.id) == [checklist])
    }

    @Test
    func unknownFolderIsRenderedAsLoose() {
        // A payload whose checklist names a folder that does not exist (the
        // cross-reference skew the loose filter guards) renders loose, never drops.
        let defaults = makeIsolatedDefaults()
        let id = UUID()
        let raw = Data(#"{"version":5,"deviceID":"d","tombstones":[],"folders":[],"checklists":[{"id":"\#(id)","name":"Groceries","items":[],"folderID":"\#(UUID().uuidString)"}]}"#.utf8)
        defaults.set(raw, forKey: "checklists.v1")
        let listVM = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))

        #expect(listVM.checklists(in: nil).map(\.id) == [id])
        #expect(listVM.folders.isEmpty)
    }
}
