import AppIntents

/// Thrown when the caller supplies a blank name or no surviving items.
enum CreateChecklistIntentError: LocalizedError {
    case blankName
    case noItems
    var errorDescription: String? {
        switch self {
        case .blankName:
            LocalizedStringResource("Give the checklist a name.", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
        case .noItems:
            LocalizedStringResource("Add at least one item.", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
        }
    }
}

public struct CreateChecklistIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Checklist"
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Name")
    public var name: String

    @Parameter(title: "Items")
    public var items: [String]

    // test seam; nil → fresh production store
    private let injectedStore: ChecklistStore?

    public init() { self.injectedStore = nil }

    @MainActor
    public init(store: ChecklistStore) { self.injectedStore = store }

    public static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$name) with \(\.$items)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = injectedStore ?? ChecklistStore(defaults: AppGroup.defaults)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CreateChecklistIntentError.blankName }
        let titles = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { throw CreateChecklistIntentError.noItems }
        let checklist = store.create(name: trimmedName, itemTitles: titles)
        return .result(dialog: IntentDialog(
            CreateChecklistDialogue.message(name: checklist.name, itemCount: checklist.items.count)))
    }
}

/// Outcome→speech mapping, next to the intent so exact text is unit-testable.
/// Keys are in the App catalog.
enum CreateChecklistDialogue {
    @MainActor
    static func message(name: String, itemCount: Int) -> LocalizedStringResource {
        guard itemCount != 1 else {
            return LocalizedStringResource(
                "Created \(name) with 1 item.", table: "Localizable", bundle: .main)
        }
        return LocalizedStringResource(
            "Created \(name) with \(itemCount) items.", table: "Localizable", bundle: .main)
    }
}
