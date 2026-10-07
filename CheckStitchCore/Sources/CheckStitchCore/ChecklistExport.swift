import Foundation

/// Serialises a selected subset of checklists as a *document* envelope: version
/// current, no device identity, no tombstones and no foreign device id. An
/// export is therefore a valid `ChecklistCodec` payload (`classify == .loaded`)
/// but never resurrects deletions or injects a foreign `deviceID` into a future
/// LWW tie-break. The folders referenced by the exported checklists ride along
/// (deduped, empty `folderTombstones`) so folder membership survives a round
/// trip.
public enum ChecklistExport {
    public static func envelope(checklists: [Checklist], from folders: [Folder]) -> ChecklistEnvelope {
        let referenced = Set(checklists.compactMap(\.folderID))
        return ChecklistEnvelope(version: ChecklistCodec.currentVersion,
                                 deviceID: "",
                                 checklists: checklists,
                                 tombstones: [],
                                 folders: folders.filter { referenced.contains($0.id) },
                                 folderTombstones: [])
    }

    public static func data(checklists: [Checklist], from folders: [Folder]) throws -> Data {
        try ChecklistCodec.encode(envelope(checklists: checklists, from: folders))
    }

    /// File name stem, no extension — the export panel supplies `.json` from the
    /// content type. Deterministic for a fixed `date`/`calendar`.
    public static func filename(for date: Date = .now, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "CheckStitch-\(formatter.string(from: date))"
    }
}