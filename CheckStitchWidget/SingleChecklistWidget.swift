import AppIntents
import CheckStitchCore
import SwiftUI
import WidgetKit

struct ChecklistEntry: TimelineEntry, Sendable {
    let date: Date
    let model: ChecklistWidgetDisplayModel
}

@MainActor
enum ChecklistWidgetLoader {
    /// Reads the App Group store and resolves the intent's configured
    /// checklists. An unconfigured widget renders the empty-state hint rather
    /// than silently running an arbitrary first checklist.
    static func load(configuration: [ChecklistEntity], at now: Date = Date()) -> ChecklistWidgetDisplayModel {
        let checklists = ChecklistStore(defaults: AppGroup.defaults).checklists
        let runState = WidgetRunStateStore(defaults: AppGroup.defaults)
        return ChecklistWidgetDisplayModel(
            checklists: checklists, configuration: configuration, access: accessState(),
            runIndicators: runState.indicators(at: now))
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
        let plan = await MainActor.run {
            ChecklistWidgetTimeline.make(configuration: configuration.checklist.map { [$0] } ?? [])
        }
        return plan.timeline
    }
}

/// What the timeline should render, read on the main actor. Kept `Sendable`
/// because `WidgetKit.Timeline` itself is not, so the provider assembles it
/// outside `MainActor.run`.
struct ChecklistWidgetPlan: Sendable {
    let entries: [ChecklistEntry]
    let reloadAfter: Date

    var timeline: Timeline<ChecklistEntry> {
        Timeline(entries: entries, policy: .after(reloadAfter))
    }
}

/// Shared timeline plan for both widgets. A run is written to
/// `WidgetRunStateStore` by `RunChecklistIntent`, and the store's reload hook
/// asks for a new timeline — this is where the spinner and the checkmark come
/// from. The second entry is what drops a visible check back to the play icon
/// without needing another reload.
@MainActor
enum ChecklistWidgetTimeline {
    static func make(configuration: [ChecklistEntity], now: Date = Date()) -> ChecklistWidgetPlan {
        let runState = WidgetRunStateStore(defaults: AppGroup.defaults)
        let entry = ChecklistEntry(
            date: now,
            model: ChecklistWidgetLoader.load(configuration: configuration, at: now))
        var entries = [entry]
        if let checkmarkEnds = runState.checkmarkEndsAt(at: now) {
            entries.append(ChecklistEntry(
                date: checkmarkEnds,
                model: ChecklistWidgetLoader.load(configuration: configuration, at: checkmarkEnds)))
        }
        // A run in flight finishes with its own reload, so the only reason to
        // re-ask is the abandoned-run timeout that unsticks a killed intent.
        let isRunning = runState.records.contains { $0.phase == .running }
        return ChecklistWidgetPlan(
            entries: entries,
            reloadAfter: now.addingTimeInterval(
                isRunning ? WidgetRunStateStore.abandonedRunTimeout : 15 * 60))
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
                        runIcon(for: row.indicator)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(row.indicator == .checkmark ? Color.green : Color.accentColor)
                    .disabled(row.indicator == .spinner)
                    .accessibilityLabel("Create reminders")
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

    /// The button's icon, mirroring the app's run button: spinner while the run
    /// is in flight, green check on success, play otherwise. Widgets render
    /// snapshots, so the `ProgressView` is a still spinner glyph, not a turning
    /// one.
    @ViewBuilder
    private func runIcon(for indicator: WidgetRunIndicator) -> some View {
        switch indicator {
        case .play:
            Image(systemName: "play.circle.fill")
                .font(.system(size: 56))
        case .spinner:
            ProgressView()
                .controlSize(.large)
                .tint(Color.white)
        case .checkmark:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
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