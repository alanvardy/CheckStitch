import Foundation

/// Human-readable phrases for an item's relative due date.
///
/// `relativeDate` is a day offset from today: `0` is today, `1` tomorrow,
/// negatives are past days, `nil` is no date — which renders blank, because
/// "no date" is the absence of a phrase rather than a phrase of its own. Shared
/// by the detail row's read-only display and the edit screen's helper caption so
/// the two sides of the screen cannot spell the same day differently.
enum DueDateLabel {
    /// `nil` renders as the empty string; every offset renders a non-empty
    /// phrase, never a bare day count.
    static func text(for relativeDate: Int?) -> String {
        guard let relativeDate else { return "" }
        switch relativeDate {
        case 0:
            return String(localized: "Today")
        case 1:
            return String(localized: "Tomorrow")
        case -1:
            return String(localized: "Yesterday")
        case 2...:
            return String(localized: "In \(relativeDate) days")
        default:
            return String(localized: "\(-relativeDate) days ago")
        }
    }
}
