import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The icon a widget's run button shows for one checklist. The app keeps this
/// in live view-model state (`ChecklistRunViewModel.creating`/`created`); a
/// widget renders from snapshots, so the phase is persisted here and read back
/// on every timeline reload.
public enum WidgetRunIndicator: Equatable, Sendable {
    case play
    case spinner
    case checkmark
}

/// One persisted widget-initiated run. `phase == .running` is written before the
/// EventKit work starts and `.finished` after it returns, so a timeline reload
/// that lands mid-run renders the spinner instead of the play icon.
public struct WidgetRunRecord: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case running
        case finished
    }

    public let checklistID: UUID
    public var phase: Phase
    public var startedAt: Date
    public var finishedAt: Date?
    /// True only for a full success (`.created`). A partial or failed run shows
    /// the play icon again — the app never flashes success for those either.
    public var didCreate: Bool

    public init(checklistID: UUID,
                phase: Phase,
                startedAt: Date,
                finishedAt: Date? = nil,
                didCreate: Bool = false) {
        self.checklistID = checklistID
        self.phase = phase
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.didCreate = didCreate
    }
}

/// Durable, per-checklist widget run phases in an injected `UserDefaults` suite
/// (the App Group in production). Validated-read convention like `RunCounter`: a
/// missing or corrupt payload reads as "no run", never throws.
///
/// `onChange` is the reload hook: every phase change asks WidgetKit for a fresh
/// timeline so the new icon actually renders. It is injectable so tests observe
/// the writes without touching WidgetKit.
@MainActor
public final class WidgetRunStateStore {
    public static let defaultsKey = "widgetRunState.v1"
    /// Minimum time a run stays `.running`, so a fast EventKit save cannot flash
    /// the spinner past the user. Matches the app's 1s `spinnerDuration` floor.
    public static let minimumSpinner: TimeInterval = 1
    /// How long the success check stays up before the play icon returns.
    public static let checkmarkDuration: TimeInterval = 1.5
    /// A `.running` record older than this is treated as abandoned (the intent
    /// was killed before it could finish), so the button can never stick on a
    /// spinner. Also the reload policy while a run is in flight.
    public static let abandonedRunTimeout: TimeInterval = 30

    /// Finished records are only kept to render the transient check; the array
    /// is capped so a long-lived install cannot grow it without bound.
    private static let recordLimit = 32

    public init(defaults: UserDefaults = AppGroup.defaults,
                key: String = WidgetRunStateStore.defaultsKey,
                minimumSpinner: TimeInterval = WidgetRunStateStore.minimumSpinner,
                onChange: @escaping @MainActor () -> Void = WidgetRunStateStore.reloadWidgets) {
        self.defaults = defaults
        self.key = key
        self.minimumSpinner = minimumSpinner
        self.onChange = onChange
        self.records = Self.decode(defaults.data(forKey: key))
    }

    /// Insertion-bounded, newest-last. Decoded once at init and written back in
    /// full on every mutation (the payload is tiny).
    public private(set) var records: [WidgetRunRecord]

    /// The floor the intent holds a run in `.running`; see `minimumSpinner`.
    public let minimumSpinner: TimeInterval

    /// Records the start of a run and asks for a reload, so the spinner can
    /// render while the EventKit work is still in flight.
    public func beginRun(id: UUID, at date: Date) {
        upsert(WidgetRunRecord(checklistID: id, phase: .running, startedAt: date))
        persist()
        onChange()
    }

    /// Records the outcome. Only `didCreate` earns the checkmark; everything
    /// else returns the button to the play icon.
    public func finishRun(id: UUID, didCreate: Bool, at date: Date) {
        let existing = records.first { $0.checklistID == id }
        upsert(WidgetRunRecord(checklistID: id,
                               phase: .finished,
                               startedAt: existing?.startedAt ?? date,
                               finishedAt: date,
                               didCreate: didCreate))
        persist()
        onChange()
    }

    /// The icon for one checklist at `now`. Pure given the stored records.
    public func indicator(for id: UUID, at now: Date) -> WidgetRunIndicator {
        guard let record = records.first(where: { $0.checklistID == id }) else { return .play }
        switch record.phase {
        case .running:
            let elapsed = now.timeIntervalSince(record.startedAt)
            return elapsed < Self.abandonedRunTimeout ? .spinner : .play
        case .finished:
            guard record.didCreate,
                  let finishedAt = record.finishedAt,
                  now.timeIntervalSince(finishedAt) < Self.checkmarkDuration
            else { return .play }
            return .checkmark
        }
    }

    /// Every known checklist's icon, for the display model.
    public func indicators(at now: Date) -> [UUID: WidgetRunIndicator] {
        Dictionary(uniqueKeysWithValues: records.map {
            ($0.checklistID, indicator(for: $0.checklistID, at: now))
        })
    }

    /// When the visible check (if any) must fall back to the play icon, so the
    /// timeline can schedule that transition instead of polling for it.
    public func checkmarkEndsAt(at now: Date) -> Date? {
        records.compactMap { record in
            guard record.didCreate,
                  let finishedAt = record.finishedAt,
                  now.timeIntervalSince(finishedAt) < Self.checkmarkDuration
            else { return nil }
            return finishedAt.addingTimeInterval(Self.checkmarkDuration)
        }.min()
    }

    /// Production `onChange`: ask WidgetKit for a fresh timeline so the next
    /// phase renders. A no-op where WidgetKit is unavailable.
    @MainActor
    public static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    private func upsert(_ record: WidgetRunRecord) {
        if let index = records.firstIndex(where: { $0.checklistID == record.checklistID }) {
            records[index] = record
        } else {
            records.append(record)
        }
        // Drop the oldest finished records first; a running record is never
        // evicted, since it is what the spinner is rendered from.
        while records.count > Self.recordLimit,
              let oldest = records.indices
                  .filter({ records[$0].phase == .finished })
                  .min(by: { records[$0].startedAt < records[$1].startedAt }) {
            records.remove(at: oldest)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode(_ data: Data?) -> [WidgetRunRecord] {
        guard let data,
              let records = try? JSONDecoder().decode([WidgetRunRecord].self, from: data)
        else { return [] }
        return records
    }

    private let defaults: UserDefaults
    private let key: String
    private let onChange: @MainActor () -> Void
}