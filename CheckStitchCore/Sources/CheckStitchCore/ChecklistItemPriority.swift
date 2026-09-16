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
    public var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}