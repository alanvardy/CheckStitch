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
}