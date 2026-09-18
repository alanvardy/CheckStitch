import Foundation

/// A checklist item's priority. Declaration order **is** `allCases` order
/// (the menu order); the raw value **is** `EKReminder.priority`'s scale, so
/// writing a reminder needs no switch.
public enum ChecklistItemPriority: Int, Codable, CaseIterable, Hashable, Sendable {
    case none = 0
    case low = 9
    case medium = 5
    case high = 1

    /// User-facing name, kept on the model so no view branches over the cases.
    /// A resource so the item editor's rows and its accessibility label follow
    /// the app language.
    public var label: LocalizedStringResource {
        switch self {
        case .none: LocalizedStringResource("None", table: "Localizable", bundle: .module)
        case .low: LocalizedStringResource("Low", table: "Localizable", bundle: .module)
        case .medium: LocalizedStringResource("Medium", table: "Localizable", bundle: .module)
        case .high: LocalizedStringResource("High", table: "Localizable", bundle: .module)
        }
    }

    /// Exclamation-marker prefix rendered before the item's name in the row:
    /// `!!!` high, `!!` medium, `!` low, empty for none. Mirrors
    /// `SingleThread`'s `ReminderPriority.Level.marker` so both apps speak the
    /// same visual language; kept on the model so no view branches over cases.
    public var marker: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }
}
