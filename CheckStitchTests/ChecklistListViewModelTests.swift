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

    @Test
    func moveFolderUpReordersFolders() {
        let viewModel = makeViewModel()
        let first = viewModel.createFolder(name: "Work")
        let second = viewModel.createFolder(name: "Personal")
        viewModel.moveFolder(id: second, up: true)
        #expect(viewModel.folders.map(\.id) == [second, first])
    }

    @Test
    func moveFolderDownReordersFolders() {
        let viewModel = makeViewModel()
        let first = viewModel.createFolder(name: "Work")
        let second = viewModel.createFolder(name: "Personal")
        viewModel.moveFolder(id: first, up: false)
        #expect(viewModel.folders.map(\.id) == [second, first])
    }

    @Test
    func renameFolderReflects() {
        let viewModel = makeViewModel()
        let folder = viewModel.createFolder(name: "Work")
        viewModel.renameFolder(id: folder, to: "Chores")
        #expect(viewModel.folders.first?.name == "Chores")
    }

    @Test
    func setFolderCollapsedReflects() {
        let viewModel = makeViewModel()
        let folder = viewModel.createFolder(name: "Work")
        viewModel.setFolderCollapsed(id: folder, true)
        #expect(viewModel.folders.first?.isCollapsed == true)
        viewModel.setFolderCollapsed(id: folder, false)
        #expect(viewModel.folders.first?.isCollapsed == false)
    }

    // MARK: Drag to move

    @Test
    func dragChecklistDownOntoRowTakesItsSlot() {
        let viewModel = makeViewModel()
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        let third = viewModel.createChecklist()
        viewModel.moveChecklist(id: first, onto: third)
        #expect(viewModel.checklists.map(\.id) == [second, third, first])
    }

    @Test
    func dragChecklistUpOntoRowTakesItsSlot() {
        let viewModel = makeViewModel()
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        let third = viewModel.createChecklist()
        viewModel.moveChecklist(id: third, onto: first)
        #expect(viewModel.checklists.map(\.id) == [third, first, second])
    }

    @Test
    func dragChecklistOntoItselfIsANoOp() {
        let viewModel = makeViewModel()
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: first, onto: first)
        #expect(viewModel.checklists.map(\.id) == [first, second])
    }

    @Test
    func dragChecklistOntoUnknownIDIsANoOp() {
        let viewModel = makeViewModel()
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: first, onto: UUID())
        #expect(viewModel.checklists.map(\.id) == [first, second])
    }

    @Test
    func dragUnknownChecklistIsANoOp() {
        let viewModel = makeViewModel()
        let first = viewModel.createChecklist()
        let second = viewModel.createChecklist()
        viewModel.moveChecklist(id: UUID(), onto: second)
        #expect(viewModel.checklists.map(\.id) == [first, second])
    }

    @Test
    func dragChecklistOntoAnotherSectionsRowIsANoOp() {
        let viewModel = makeViewModel()
        let folder = viewModel.createFolder(name: "Work")
        let filed = viewModel.createChecklist()
        let loose = viewModel.createChecklist()
        viewModel.moveChecklist(id: filed, toFolder: folder)

        viewModel.moveChecklist(id: filed, onto: loose)

        let f = viewModel.folders.first { $0.id == folder }!
        #expect(viewModel.checklists(in: f).map(\.id) == [filed])
        #expect(viewModel.checklists(in: nil).map(\.id) == [loose])
    }

    @Test
    func dragChecklistWithinFolderReordersAroundOtherFoldersMembers() {
        // Global order [c1(fA), x(fB), c2(fA)]: the mapping must skip x entirely.
        let viewModel = makeViewModel()
        let folderA = viewModel.createFolder(name: "Work")
        let folderB = viewModel.createFolder(name: "Personal")
        let c1 = viewModel.createChecklist()
        let x = viewModel.createChecklist()
        let c2 = viewModel.createChecklist()
        viewModel.moveChecklist(id: c1, toFolder: folderA)
        viewModel.moveChecklist(id: x, toFolder: folderB)
        viewModel.moveChecklist(id: c2, toFolder: folderA)

        viewModel.moveChecklist(id: c1, onto: c2)

        let a = viewModel.folders.first { $0.id == folderA }!
        let b = viewModel.folders.first { $0.id == folderB }!
        #expect(viewModel.checklists(in: a).map(\.id) == [c2, c1])
        #expect(viewModel.checklists(in: b).map(\.id) == [x])
    }

    @Test
    func dragChecklistOrderPersistsAndReloads() {
        let defaults = makeIsolatedDefaults()
        let first = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))
        let a = first.createChecklist()
        let b = first.createChecklist()
        first.moveChecklist(id: b, onto: a)

        let reloaded = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))
        #expect(reloaded.checklists.map(\.id) == [b, a])
    }

    @Test
    func dragFolderDownOntoFolderTakesItsSlot() {
        let viewModel = makeViewModel()
        let first = viewModel.createFolder(name: "Work")
        let second = viewModel.createFolder(name: "Personal")
        let third = viewModel.createFolder(name: "Errands")
        viewModel.moveFolder(id: first, onto: third)
        #expect(viewModel.folders.map(\.id) == [second, third, first])
    }

    @Test
    func dragFolderUpOntoFolderTakesItsSlot() {
        let viewModel = makeViewModel()
        let first = viewModel.createFolder(name: "Work")
        let second = viewModel.createFolder(name: "Personal")
        let third = viewModel.createFolder(name: "Errands")
        viewModel.moveFolder(id: third, onto: first)
        #expect(viewModel.folders.map(\.id) == [third, first, second])
    }

    @Test
    func dragFolderOntoItselfIsANoOp() {
        let viewModel = makeViewModel()
        let first = viewModel.createFolder(name: "Work")
        let second = viewModel.createFolder(name: "Personal")
        viewModel.moveFolder(id: first, onto: first)
        #expect(viewModel.folders.map(\.id) == [first, second])
    }

    @Test
    func dragFolderOntoUnknownIDIsANoOp() {
        let viewModel = makeViewModel()
        let only = viewModel.createFolder(name: "Work")
        viewModel.moveFolder(id: only, onto: UUID())
        #expect(viewModel.folders.map(\.id) == [only])
    }

    @Test
    func dragFolderOrderPersistsAndReloads() {
        let defaults = makeIsolatedDefaults()
        let first = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))
        let a = first.createFolder(name: "Work")
        let b = first.createFolder(name: "Personal")
        first.moveFolder(id: b, onto: a)

        let reloaded = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))
        #expect(reloaded.folders.map(\.id) == [b, a])
    }

    // MARK: Archive

    @Test
    func archivedChecklistsAreExcludedFromTheList() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let active = store.create().id
        let archived = store.create().id
        store.archive(id: archived)

        let viewModel = ChecklistListViewModel(store: store)
        #expect(viewModel.checklists.map(\.id) == [active])
    }

    @Test
    func emptyStateFollowsActiveChecklists() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let only = store.create().id
        store.archive(id: only)

        let viewModel = ChecklistListViewModel(store: store)
        #expect(viewModel.checklists.isEmpty)
    }

    @Test
    func archivedChecklistsAreHiddenInsideFolders() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let folderID = store.createFolder(name: "Errands").id
        let active = store.create().id
        let archived = store.create().id
        store.moveChecklist(id: active, toFolder: folderID)
        store.moveChecklist(id: archived, toFolder: folderID)
        store.archive(id: archived)

        let viewModel = ChecklistListViewModel(store: store)
        let folder = viewModel.folders.first { $0.id == folderID }!
        #expect(viewModel.checklists(in: folder).map(\.id) == [active])
    }

    @Test
    func moveChecklistUpSkipsAnArchivedRow() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let first = store.create(name: "First").id
        let archived = store.create(name: "Archived").id
        let third = store.create(name: "Third").id
        store.archive(id: archived)

        let viewModel = ChecklistListViewModel(store: store)
        viewModel.moveChecklist(id: third, up: true)

        #expect(viewModel.checklists.map(\.id) == [third, first])
    }
}
