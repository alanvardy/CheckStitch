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
        #expect(model.rows.allSatisfy { $0.needsPurchase == (access == .needsPurchase) })
    }

    @Test
    func readyAccessMakesRowsRunnable() {
        let checklist = Checklist(name: "Groceries")
        let model = ChecklistWidgetDisplayModel(
            checklists: [checklist],
            configuration: [ChecklistEntity(checklist)],
            access: .ready)
        #expect(model.rows.allSatisfy { $0.isRunnable && !$0.needsAccess && !$0.needsPurchase })
    }

    /// The empty-state hint needs to tell "nothing configured yet" (offer the
    /// edit affordance) from "nothing to configure" (the store is empty).
    @Test
    func hasChecklistsDistinguishesUnconfiguredFromEmptyStore() {
        let unconfigured = ChecklistWidgetDisplayModel(
            checklists: [Checklist(name: "Groceries")], configuration: [], access: .ready)
        #expect(unconfigured.rows.isEmpty)
        #expect(unconfigured.hasChecklists)

        let emptyStore = ChecklistWidgetDisplayModel(
            checklists: [], configuration: [], access: .ready)
        #expect(emptyStore.rows.isEmpty)
        #expect(!emptyStore.hasChecklists)
    }

    @Test
    func runIndicatorIsCarriedOntoItsRow() {
        let groceries = Checklist(name: "Groceries")
        let packing = Checklist(name: "Packing")
        let model = ChecklistWidgetDisplayModel(
            checklists: [groceries, packing],
            configuration: [ChecklistEntity(groceries), ChecklistEntity(packing)],
            access: .ready,
            runIndicators: [groceries.id: .spinner, packing.id: .checkmark])

        #expect(model.rows.first { $0.id == groceries.id }?.indicator == .spinner)
        #expect(model.rows.first { $0.id == packing.id }?.indicator == .checkmark)
    }

    /// No persisted run → the button is a play icon, not a spinner.
    @Test
    func rowsWithoutARunShowThePlayIcon() {
        let checklist = Checklist(name: "Groceries")
        let model = ChecklistWidgetDisplayModel(
            checklists: [checklist],
            configuration: [ChecklistEntity(checklist)],
            access: .ready)

        #expect(model.rows.allSatisfy { $0.indicator == .play })
    }

    @Test
    func archivedConfiguredChecklistProducesNoRows() {
        let archived = Checklist(name: "Archived", isArchived: true)
        let model = ChecklistWidgetDisplayModel(
            checklists: [archived],
            configuration: [ChecklistEntity(archived)],
            access: .ready)

        #expect(model.rows.isEmpty)
    }

    @Test
    func hasChecklistsIsFalseWhenOnlyArchivedAreConfigured() {
        let archived = Checklist(name: "Archived", isArchived: true)
        let model = ChecklistWidgetDisplayModel(
            checklists: [archived],
            configuration: [],
            access: .ready)

        #expect(model.rows.isEmpty)
        #expect(!model.hasChecklists)
    }
}