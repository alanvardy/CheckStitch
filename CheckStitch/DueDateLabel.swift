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
    /// phrase, never a bare day count. Returned as a resource so SwiftUI
    /// re-resolves it against the environment locale on a language switch.
    static func resource(for relativeDate: Int?) -> LocalizedStringResource {
        guard let relativeDate else {
            return LocalizedStringResource("", table: "Localizable", bundle: .main)
        }
        switch relativeDate {
        case 0:
            return LocalizedStringResource("Today", table: "Localizable", bundle: .main)
        case 1:
            return LocalizedStringResource("Tomorrow", table: "Localizable", bundle: .main)
        case -1:
            return LocalizedStringResource("Yesterday", table: "Localizable", bundle: .main)
        case 2...:
            return LocalizedStringResource("In \(relativeDate) days", table: "Localizable", bundle: .main)
        default:
            return LocalizedStringResource("\(-relativeDate) days ago", table: "Localizable", bundle: .main)
        }
    }
}
