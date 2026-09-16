import AppIntents

struct ListChecklistsIntent: AppIntent {
    static let title: LocalizedStringResource = "List My Checklists"
    static let openAppWhenRun: Bool = false

    private let query: ChecklistEntityQuery

    init() { self.query = ChecklistEntityQuery() }
    @MainActor
    init(store: ChecklistStore) { self.query = ChecklistEntityQuery(store: store) }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let names = try await query.suggestedEntities().map(\.name)
        return .result(dialog: IntentDialog(ListChecklistsDialogue.message(for: names)))
    }
}

/// Names→speech mapping. Lives here (not in the intent body) so exact text is
/// unit-testable without a speech stack. Keys are in the app catalog.
enum ListChecklistsDialogue {
    @MainActor
    static func message(for names: [String]) -> LocalizedStringResource {
        guard !names.isEmpty else {
            return LocalizedStringResource(
                "You don't have any checklists yet.", table: "Localizable", bundle: .main)
        }
        guard names.count != 1 else {
            return LocalizedStringResource(
                "You have 1 checklist: \(names.joined(separator: ", ")).",
                table: "Localizable", bundle: .main)
        }
        return LocalizedStringResource(
            "You have \(names.count) checklists: \(names.joined(separator: ", ")).",
            table: "Localizable", bundle: .main)
    }
}
