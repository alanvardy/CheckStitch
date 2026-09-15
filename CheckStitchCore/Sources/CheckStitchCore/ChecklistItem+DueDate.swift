import Foundation

extension ChecklistItem {
    /// The date-only due-date components for a reminder, or `nil` when the item
    /// carries no relative date. `0` is today, `1` tomorrow, negatives are past
    /// days. Time components are deliberately absent: CheckStitch has no
    /// time-of-day support.
    ///
    /// `calendar` is injectable so tests can pin a time zone; production callers
    /// use the device-local `.current`, matching the SingleThread precedent.
    public func dueDateComponents(today: Date, calendar: Calendar = .current) -> DateComponents? {
        guard let relativeDate else { return nil }
        guard let target = calendar.date(
            byAdding: .day,
            value: relativeDate,
            to: calendar.startOfDay(for: today)
        ) else { return nil }
        return calendar.dateComponents([.year, .month, .day], from: target)
    }
}
