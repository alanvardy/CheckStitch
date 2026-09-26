import CheckStitchCore
import Foundation
import Testing

struct ChecklistWidgetDisplayModelTests {
    @Test
    func configuredChecklistBecomesARunnableRow() {
        let checklist = Checklist(name: "Groceries")
        let model = ChecklistWidgetDisplayModel(
            checklists: [checklist],
            configuration: [ChecklistEntity(checklist)],
            access: .ready)
        #expect(model.rows.map(\.name) == ["Groceries"])
        #expect(model.rows.first?.isRunnable == true)
        #expect(model.rows.first?.needsAccess == false)
    }

    @Test
    func emptyChecklistsProduceNoRows() {
        let model = ChecklistWidgetDisplayModel(
            checklists: [], configuration: [], access: .ready)
        #expect(model.rows.isEmpty)
    }

    @Test
    func selectedEntityResolvesToItsRowWhateverTheStoreOrder() {
        let groceries = Checklist(name: "Groceries")
        let packing = Checklist(name: "Packing")
        let model = ChecklistWidgetDisplayModel(
            checklists: [groceries, packing],
            configuration: [ChecklistEntity(packing)],
            access: .ready)
        #expect(model.rows.map(\.name) == ["Packing"])
    }

    @Test
    func configurationOrderIsPreservedAndMissingEntitiesAreDropped() {
        let a = Checklist(name: "A")
        let b = Checklist(name: "B")
        let c = Checklist(name: "C")
        let model = ChecklistWidgetDisplayModel(
            checklists: [a, b, c],
            configuration: [ChecklistEntity(c), ChecklistEntity(id: UUID().uuidString, name: "Ghost"), ChecklistEntity(a)],
            access: .ready)
        #expect(model.rows.map(\.name) == ["C", "A"])
    }

    @Test
    func rowsAreCappedToTheRowBudget() {
        let checklists = (0..<9).map { Checklist(name: "List \($0)") }
        let model = ChecklistWidgetDisplayModel(
            checklists: checklists,
            configuration: checklists.map(ChecklistEntity.init),
            access: .ready)
        #expect(model.rows.count == ChecklistWidgetDisplayModel.rowLimit)
        #expect(model.rows.map(\.name) == (0..<ChecklistWidgetDisplayModel.rowLimit).map { "List \($0)" })
    }

    @Test
    func ghostEntityProducesNoRows() {
        let model = ChecklistWidgetDisplayModel(
            checklists: [Checklist(name: "Groceries")],
            configuration: [ChecklistEntity(id: UUID().uuidString, name: "Deleted")],
            access: .ready)
        #expect(model.rows.isEmpty)
    }

    @Test(arguments: [ChecklistWidgetAccessState.needsAccess, .needsPurchase])
    func nonReadyAccessMakesEveryRowNonRunnable(_ access: ChecklistWidgetAccessState) {
        let checklist = Checklist(name: "Groceries")
        let model = ChecklistWidgetDisplayModel(
            checklists: [checklist],
            configuration: [ChecklistEntity(checklist)],
            access: access)
        #expect(model.rows.allSatisfy { !$0.isRunnable && $0.needsAccess })
    }

    @Test
    func readyAccessMakesRowsRunnable() {
        let checklist = Checklist(name: "Groceries")
        let model = ChecklistWidgetDisplayModel(
            checklists: [checklist],
            configuration: [ChecklistEntity(checklist)],
            access: .ready)
        #expect(model.rows.allSatisfy { $0.isRunnable && !$0.needsAccess })
    }
}