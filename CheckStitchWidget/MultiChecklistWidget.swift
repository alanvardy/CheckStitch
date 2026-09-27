import AppIntents
import CheckStitchCore
import SwiftUI
import WidgetKit

struct MultiChecklistProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry {
        ChecklistEntry(
            date: .now,
            model: ChecklistWidgetDisplayModel(
                checklists: [Checklist(name: "Groceries"), Checklist(name: "Packing")],
                configuration: [ChecklistEntity(id: UUID().uuidString, name: "Groceries"),
                                ChecklistEntity(id: UUID().uuidString, name: "Packing")],
                access: .ready))
    }

    func snapshot(for configuration: MultiChecklistConfigurationIntent, in context: Context) async -> ChecklistEntry {
        let model = await MainActor.run {
            ChecklistWidgetLoader.load(configuration: configuration.checklists ?? [])
        }
        return ChecklistEntry(date: .now, model: model)
    }

    func timeline(for configuration: MultiChecklistConfigurationIntent, in context: Context) async -> Timeline<ChecklistEntry> {
        let plan = await MainActor.run {
            ChecklistWidgetTimeline.make(configuration: configuration.checklists ?? [])
        }
        return plan.timeline
    }
}

struct MultiChecklistWidget: Widget {
    static let kind = "MultiChecklistWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: MultiChecklistConfigurationIntent.self,
                               provider: MultiChecklistProvider()) { entry in
            MultiChecklistWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CheckStitch Checklists")
        .description("Run any of your checklists without opening the app.")
        .supportedFamilies([.systemLarge])
    }
}

struct MultiChecklistWidgetView: View {
    let entry: ChecklistEntry

    var body: some View {
        if entry.model.rows.isEmpty {
            Text(entry.model.hasChecklists
                 ? "Edit this widget to pick a checklist"
                 : "No checklists")
                .font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.model.rows) { row in
                    HStack {
                        Text(row.name).font(.title3).lineLimit(1)
                        Spacer()
                        if row.isRunnable {
                            Button(intent: runIntent(for: row)) {
                                runIcon(for: row.indicator)
                            }
                            .buttonStyle(.plain)
                            .disabled(row.indicator == .spinner)
                        } else if row.needsPurchase {
                            Label("Open CheckStitch to buy a license", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                        } else {
                            Label("Open CheckStitch to enable", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                        }
                    }
                    .widgetURL(row.needsAccess ? URL(string: "checkstitch://") : nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Per-row run icon, mirroring the app: spinner while in flight, green check
    /// on success, play otherwise.
    @ViewBuilder
    private func runIcon(for indicator: WidgetRunIndicator) -> some View {
        switch indicator {
        case .play:
            Image(systemName: "play.circle.fill")
        case .spinner:
            ProgressView()
                .controlSize(.small)
        case .checkmark:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @MainActor
    private func runIntent(for row: ChecklistWidgetRow) -> RunChecklistIntent {
        let intent = RunChecklistIntent()
        intent.checklist = ChecklistEntity(id: row.entityID, name: row.name)
        return intent
    }
}

// MARK: - Previews

#Preview("Checklists", as: .systemLarge) {
    MultiChecklistWidget()
} timeline: {
    ChecklistEntry(
        date: Date(),
        model: ChecklistWidgetDisplayModel(
            checklists: [Checklist(name: "Groceries"), Checklist(name: "Packing")],
            configuration: [ChecklistEntity(id: UUID().uuidString, name: "Groceries"),
                            ChecklistEntity(id: UUID().uuidString, name: "Packing")],
            access: .ready))
}