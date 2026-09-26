import AppIntents
import CheckStitchCore
import SwiftUI
import WidgetKit

struct ChecklistEntry: TimelineEntry {
    let date: Date
    let model: ChecklistWidgetDisplayModel
}

@MainActor
enum ChecklistWidgetLoader {
    /// Reads the App Group store and folds access state. Phase 1 hard-codes the
    /// first checklist; later phases pass the intent's configuration.
    static func load(configuration: [ChecklistEntity]) -> ChecklistWidgetDisplayModel {
        let checklists = ChecklistStore(defaults: AppGroup.defaults).checklists
        let resolved = configuration.isEmpty
            ? checklists.first.map { [ChecklistEntity($0)] } ?? []
            : configuration
        return ChecklistWidgetDisplayModel(
            checklists: checklists, configuration: resolved, access: accessState())
    }

    static func accessState() -> ChecklistWidgetAccessState {
        EventKitReminderDestination.shared.accessStatus() == .fullAccess
            ? .ready : .needsAccess
    }
}

struct SingleChecklistProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry {
        ChecklistEntry(
            date: .now,
            model: ChecklistWidgetDisplayModel(
                checklists: [Checklist(name: "Groceries")],
                configuration: [ChecklistEntity(id: UUID().uuidString, name: "Groceries")],
                access: .ready))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ChecklistEntry) -> Void) {
        Task { @MainActor in
            completion(ChecklistEntry(date: .now, model: ChecklistWidgetLoader.load(configuration: [])))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ChecklistEntry>) -> Void) {
        Task { @MainActor in
            let entry = ChecklistEntry(date: .now, model: ChecklistWidgetLoader.load(configuration: []))
            completion(Timeline(entries: [entry],
                                policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct SingleChecklistWidget: Widget {
    static let kind = "SingleChecklistWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SingleChecklistProvider()) { entry in
            SingleChecklistWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CheckStitch Checklist")
        .description("Run a checklist without opening the app.")
        .supportedFamilies([.systemSmall])
    }
}

struct SingleChecklistWidgetView: View {
    let entry: ChecklistEntry

    var body: some View {
        if let row = entry.model.rows.first {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.name).font(.headline).lineLimit(2)
                if row.isRunnable {
                    Button(intent: runIntent(for: row)) {
                        Label("Create reminders", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("Open CheckStitch to enable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("No checklists").font(.caption)
        }
    }

    /// `RunChecklistIntent` has no memberwise init (its `@Parameter` is set by the
    /// system / here). Build it and assign the parameter.
    @MainActor
    private func runIntent(for row: ChecklistWidgetRow) -> RunChecklistIntent {
        let intent = RunChecklistIntent()
        intent.checklist = ChecklistEntity(id: row.entityID, name: row.name)
        return intent
    }
}