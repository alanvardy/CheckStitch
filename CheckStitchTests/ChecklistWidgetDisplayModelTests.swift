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
    func ghostEntityProducesNoRows() {
        let model = ChecklistWidgetDisplayModel(
            checklists: [Checklist(name: "Groceries")],
            configuration: [ChecklistEntity(id: UUID().uuidString, name: "Deleted")],
            access: .ready)
        #expect(model.rows.isEmpty)
    }
}