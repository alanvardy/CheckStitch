@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ChecklistGroupingTests {
    @Test
    func membersFollowGlobalOrder() {
        let folder = Folder(name: "Errands")
        let first = Checklist(name: "First", folderID: folder.id)
        let second = Checklist(name: "Second", folderID: folder.id)

        let sections = ChecklistGrouping.sections(folders: [folder], checklists: [first, second])

        #expect(sections.first?.folder?.id == folder.id)
        #expect(sections.first?.checklists == [first, second])
    }

    @Test
    func looseSectionIsLast() {
        let folder = Folder(name: "Errands")
        let inFolder = Checklist(name: "In folder", folderID: folder.id)
        let loose = Checklist(name: "Loose")

        let sections = ChecklistGrouping.sections(folders: [folder], checklists: [loose, inFolder])

        #expect(sections.last?.folder == nil)
        #expect(sections.last?.checklists == [loose])
    }

    @Test
    func unknownFolderIDFallsIntoLoose() {
        let orphan = Checklist(name: "Orphan", folderID: UUID())

        let sections = ChecklistGrouping.sections(folders: [], checklists: [orphan])

        #expect(sections.count == 1)
        #expect(sections.first?.folder == nil)
        #expect(sections.first?.checklists == [orphan])
    }

    @Test
    func emptyFolderProducesAnEmptySection() {
        let folder = Folder(name: "Empty")

        let sections = ChecklistGrouping.sections(folders: [folder], checklists: [])

        #expect(sections.first?.folder?.id == folder.id)
        #expect(sections.first?.checklists == [])
    }

    @Test
    func emptyFolderWithLooseMembersRendersLooseLast() {
        let folder = Folder(name: "Empty")
        let loose = Checklist(name: "Loose")

        let sections = ChecklistGrouping.sections(folders: [folder], checklists: [loose])

        #expect(sections.count == 2)
        #expect(sections[0].folder?.id == folder.id)
        #expect(sections[0].checklists == [])
        #expect(sections[1].folder == nil)
        #expect(sections.last?.checklists == [loose])
    }

    @Test
    func visibleLooseChecklistsExcludeHiddenChecklists() {
        let shown = Checklist(name: "Shown")
        let hidden = Checklist(name: "Hidden", showsOnWatch: false)

        let visible = ChecklistGrouping.visibleLooseChecklists([shown, hidden], knownFolderIDs: [])

        #expect(visible == [shown])
    }

    @Test
    func visibleChecklistsInFolderExcludeHiddenChecklists() {
        let folder = Folder(name: "Errands")
        let shown = Checklist(name: "Shown", folderID: folder.id)
        let hidden = Checklist(name: "Hidden", showsOnWatch: false, folderID: folder.id)

        let visible = ChecklistGrouping.visibleChecklists(in: folder, from: [hidden, shown])

        #expect(visible == [shown])
    }

    @Test
    func folderWithSomeVisibleMembersStaysVisible() {
        let folder = Folder(name: "Errands")
        let shown = Checklist(name: "Shown", folderID: folder.id)
        let hidden = Checklist(name: "Hidden", showsOnWatch: false, folderID: folder.id)

        let visible = ChecklistGrouping.visibleFolders([folder], checklists: [hidden, shown])

        #expect(visible == [folder])
    }

    @Test
    func folderWithEveryMemberHiddenIsHidden() {
        let folder = Folder(name: "Errands")
        let hidden = Checklist(name: "Hidden", showsOnWatch: false, folderID: folder.id)

        let visible = ChecklistGrouping.visibleFolders([folder], checklists: [hidden])

        #expect(visible.isEmpty)
    }

    @Test
    func emptyFolderStaysVisible() {
        let folder = Folder(name: "Empty")

        let visible = ChecklistGrouping.visibleFolders([folder], checklists: [])

        #expect(visible == [folder])
    }

    @Test
    func hiddenChecklistWithUnknownFolderIsNotShownAsLoose() {
        let hidden = Checklist(name: "Hidden", showsOnWatch: false, folderID: UUID())
        let visible = Checklist(name: "Visible", folderID: UUID())

        let loose = ChecklistGrouping.visibleLooseChecklists([hidden, visible], knownFolderIDs: [])

        #expect(loose == [visible])
    }

    @Test
    func hiddenChecklistWithTombstonedFolderIsNotShown() {
        let tombstoned = UUID()
        let hidden = Checklist(name: "Hidden", showsOnWatch: false, folderID: tombstoned)
        let shown = Checklist(name: "Shown", folderID: tombstoned)

        let loose = ChecklistGrouping.visibleLooseChecklists([hidden, shown], knownFolderIDs: [])

        #expect(loose == [shown])
        #expect(!loose.contains(hidden))
    }
}
