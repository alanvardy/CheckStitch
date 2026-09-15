import Foundation

/// Serialises a selected subset of checklists as a *document* envelope: version
/// current, no device identity, no tombstones. An export is therefore a valid
/// `ChecklistCodec` payload (`classify == .loaded`) but never resurrects
/// deletions or injects a foreign `deviceID` into a future LWW tie-break.
public enum ChecklistExport {
    public static func envelope(checklists: [Checklist]) -> ChecklistEnvelope {
        ChecklistEnvelope(version: ChecklistCodec.currentVersion,
                          deviceID: "",
                          checklists: checklists,
                          tombstones: [])
    }

    public static func data(checklists: [Checklist]) throws -> Data {
        try ChecklistCodec.encode(envelope(checklists: checklists))
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