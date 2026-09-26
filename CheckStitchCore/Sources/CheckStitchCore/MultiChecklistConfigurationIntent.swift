import AppIntents

public struct MultiChecklistConfigurationIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Checklists"
    public static let description = IntentDescription("Pick the checklists this widget runs.")

    @Parameter(title: "Checklists")
    public var checklists: [ChecklistEntity]?

    public init() {}
}