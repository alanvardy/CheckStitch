import Foundation

/// Editable row model for a checklist item. The ID is stable so rows can be
/// added, removed, and edited without conflating duplicate titles.
public struct ChecklistItem: Identifiable, Equatable, Sendable {
    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }

    public let id: UUID
    public var title: String

    /// A title that is empty or whitespace/newlines only. Creation skips these
    /// so an emptied row can't produce a meaningless reminder.
    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
