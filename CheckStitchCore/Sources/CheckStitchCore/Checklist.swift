import Foundation
import os

/// Editable row model for a checklist item. The ID is stable so rows can be
/// added, removed, and edited without conflating duplicate titles.
public struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
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

/// A named collection of items that can be turned into reminders.
public struct Checklist: Identifiable, Codable, Hashable, Sendable {
    public init(id: UUID = UUID(), name: String = "New checklist", items: [ChecklistItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }

    public let id: UUID
    public var name: String
    public var items: [ChecklistItem]
}

/// Versioned wire format for the App Group payload. The version field exists so
/// VAR-963 can evolve decoding instead of silently mis-reading old data.
public struct ChecklistEnvelope: Codable, Sendable {
    public init(version: Int, checklists: [Checklist]) {
        self.version = version
        self.checklists = checklists
    }

    public var version: Int
    public var checklists: [Checklist]
}

public enum ChecklistCodec {
    public static let currentVersion = 1

    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistCodec")

    /// How a stored payload relates to the version this build understands.
    public enum Outcome: Equatable {
        case loaded([Checklist])
        /// Written by a future version whose shape is unknown.
        case unsupportedVersion
        /// Garbage that is safe to replace.
        case unreadable
    }

    public static func encode(_ checklists: [Checklist]) throws -> Data {
        try JSONEncoder().encode(ChecklistEnvelope(version: currentVersion, checklists: checklists))
    }

    /// Classifies a payload — never a crash, never a partial decode.
    public static func classify(_ data: Data) -> Outcome {
        do {
            let envelope = try JSONDecoder().decode(ChecklistEnvelope.self, from: data)
            guard envelope.version == currentVersion else {
                logger.error("Unsupported checklist payload version \(envelope.version, privacy: .public); treating as empty")
                return .unsupportedVersion
            }
            return .loaded(envelope.checklists)
        } catch {
            logger.error("Failed to decode checklist payload: \(error.localizedDescription, privacy: .public)")
            return .unreadable
        }
    }

    /// Convenience for readers that only need the values.
    public static func decode(_ data: Data) -> [Checklist] {
        if case .loaded(let checklists) = classify(data) { return checklists }
        return []
    }
}