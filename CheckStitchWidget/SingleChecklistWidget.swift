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
    /// Reads the App Group store and resolves the intent's configured
    /// checklists. An unconfigured widget renders the empty-state hint rather
    /// than silently running an arbitrary first checklist.
    static func load(configuration: [ChecklistEntity]) -> ChecklistWidgetDisplayModel {
        let checklists = ChecklistStore(defaults: AppGroup.defaults).checklists
        return ChecklistWidgetDisplayModel(
            checklists: checklists, configuration: configuration, access: accessState())
    }

    static func accessState() -> ChecklistWidgetAccessState {
        switch EventKitReminderDestination.shared.accessStatus() {
        case .fullAccess:
            let unlocked = PurchaseEntitlementCache(defaults: AppGroup.defaults).isVerified
            let used = RunCounter(defaults: AppGroup.defaults).count
            return (!unlocked && used >= RunGate.freeRunLimit) ? .needsPurchase : .ready
        case .notDetermined, .denied:
            return .needsAccess
        }
    }
}

struct SingleChecklistProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry {
        ChecklistEntry(
            date: .now,
            model: ChecklistWidgetDisplayModel(
                checklists: [Checklist(name: "Groceries")],
                configuration: [ChecklistEntity(id: UUID().uuidString, name: "Groceries")],
                access: .ready))
    }

    func snapshot(for configuration: ChecklistConfigurationIntent, in context: Context) async -> ChecklistEntry {
        let model = await MainActor.run {
            ChecklistWidgetLoader.load(configuration: configuration.checklist.map { [$0] } ?? [])
        }
        return ChecklistEntry(date: .now, model: model)
    }

    func timeline(for configuration: ChecklistConfigurationIntent, in context: Context) async -> Timeline<ChecklistEntry> {
        let model = await MainActor.run {
            ChecklistWidgetLoader.load(configuration: configuration.checklist.map { [$0] } ?? [])
        }
        return Timeline(entries: [ChecklistEntry(date: .now, model: model)],
                        policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

struct SingleChecklistWidget: Widget {
    static let kind = "SingleChecklistWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ChecklistConfigurationIntent.self, provider: SingleChecklistProvider()) { entry in
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
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                            .accessibilityLabel("Create reminders")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if row.needsPurchase {
                    Label("Open CheckStitch to buy a license", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                } else {
                    Label("Open CheckStitch to enable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(row.needsAccess ? URL(string: "checkstitch://") : nil)
        } else {
            Text(entry.model.hasChecklists
                 ? "Edit this widget to pick a checklist"
                 : "No checklists")
                .font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

// MARK: - Previews

#Preview("Checklist", as: .systemSmall) {
    SingleChecklistWidget()
} timeline: {
    ChecklistEntry(
        date: Date(),
        model: ChecklistWidgetDisplayModel(
            checklists: [Checklist(name: "Groceries")],
            configuration: [ChecklistEntity(id: UUID().uuidString, name: "Groceries")],
            access: .ready))
}