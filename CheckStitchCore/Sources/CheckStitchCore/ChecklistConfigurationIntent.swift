import AppIntents

public struct ChecklistConfigurationIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Checklist"
    public static let description = IntentDescription("Pick the checklist this widget runs.")

    @Parameter(title: "Checklist")
    public var checklist: ChecklistEntity?

    public init() {}
}