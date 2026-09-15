import CheckStitchCore
import Foundation

/// A blocking, pre-mutation import failure. Plain-English `message` mirrors
/// `ReminderRunOutcome.errorMessage` (mapped in core so it is unit-testable and
/// not a localized-catalog key).
enum ChecklistImportError: Error, Equatable {
    case unreadable
    case unsupportedVersion

    var message: String {
        switch self {
        case .unreadable: return "This file isn't a CheckStitch export."
        case .unsupportedVersion: return "This file was created by a newer version of CheckStitch."
        }
    }
}

/// One decoded checklist presented to the import flow. `conflicting` is the
/// local checklist it collides with, or `nil` when it was inserted immediately.
struct ChecklistImportCandidate: Identifiable, Equatable {
    let id: UUID
    let checklist: Checklist
    let conflicting: Checklist?
}

enum ImportDecision: Equatable { case replace, keepBoth, keepExisting }

struct ImportSummary: Equatable {
    var inserted = 0
    var replaced = 0
    var keptBoth = 0
    var keptExisting = 0
}

/// Turns raw file bytes into an ordered candidate list and applies the user's
/// per-conflict decisions to the store. `@Observable` so the SwiftUI conflict
/// dialog can track `pending`.
@MainActor
@Observable
final class ChecklistImportSession {
    private let store: ChecklistStore
    private let now: () -> Date

    /// Conflicts awaiting a decision, in file order.
    private(set) var pending: [ChecklistImportCandidate] = []
    private(set) var summary = ImportSummary()

    init(store: ChecklistStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// Decodes `data`, inserts every non-conflicting checklist immediately
    /// (`importInsert`), and returns all candidates in file order. Throws for a
    /// payload this build cannot read or does not understand, leaving the store
    /// untouched. Prior `pending`/`summary` are reset at entry, so one session
    /// per file is idempotent even across a throwing call.
    @discardableResult
    func prepare(data: Data) throws -> [ChecklistImportCandidate] {
        pending = []
        summary = ImportSummary()

        let incoming: [Checklist]
        switch ChecklistCodec.classify(data) {
        case .loaded(let envelope):
            incoming = envelope.checklists
        case .migratable(let from, let envelope):
            // Legacy shapes are normalised before conflict detection for
            // symmetry with the store's own load path. `freshCopy` regenerates
            // every id/revision/order field below, so this does not itself
            // change what gets inserted.
            incoming = envelope.checklists.map { checklist in
                switch from {
                case 1: return checklist.migrated(at: now())
                case 2: return checklist.seededOrder()
                default: return checklist
                }
            }
        case .unsupportedVersion:
            throw ChecklistImportError.unsupportedVersion
        case .unreadable:
            throw ChecklistImportError.unreadable
        }

        var candidates: [ChecklistImportCandidate] = []
        for checklist in incoming {
            if let conflict = store.conflictingChecklist(named: checklist.name) {
                let candidate = ChecklistImportCandidate(
                    id: UUID(), checklist: checklist, conflicting: conflict)
                pending.append(candidate)
                candidates.append(candidate)
            } else {
                store.importInsert(checklist)
                summary.inserted += 1
                candidates.append(ChecklistImportCandidate(
                    id: UUID(), checklist: checklist, conflicting: nil))
            }
        }
        return candidates
    }

    /// Applies one conflict decision and removes the candidate from the queue.
    /// A replace whose local target vanished is counted as neither.
    func decide(_ decision: ImportDecision, for candidateID: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == candidateID }) else { return }
        let candidate = pending.remove(at: index)
        switch decision {
        case .replace:
            if let conflict = candidate.conflicting,
               store.importReplace(id: conflict.id, with: candidate.checklist) != nil {
                summary.replaced += 1
            }
        case .keepBoth:
            store.importInsert(candidate.checklist)   // auto-disambiguates via uniqueName
            summary.keptBoth += 1
        case .keepExisting:
            summary.keptExisting += 1
        }
    }
}