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

/// One decoded checklist presented to the import flow. `id` is the FILE's
/// checklist id (stable across stage/commit and with the selection set);
/// `conflicting` is the local checklist it collides with, or `nil`.
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
    /// The staged checklists presented for selection, in file order.
    private(set) var candidates: [ChecklistImportCandidate] = []
    private(set) var summary = ImportSummary()

    init(store: ChecklistStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// Decodes `data` and exposes the file's checklists for selection WITHOUT
    /// touching the store (only the read-only `conflictingChecklist` is called).
    /// Throws for a payload this build cannot read or understand, before any
    /// staging. Prior candidates/pending/summary are reset at entry.
    @discardableResult
    func stage(data: Data) throws -> [ChecklistImportCandidate] {
        pending = []
        summary = ImportSummary()
        candidates = []
        let incoming = try decoded(data)
        candidates = incoming.map { checklist in
            ChecklistImportCandidate(
                id: checklist.id,
                checklist: checklist,
                conflicting: store.conflictingChecklist(named: checklist.name))
        }
        return candidates
    }

    /// Imports exactly `selectedIDs`, in file order. The conflict check is
    /// re-run here (authoritative): a selected name that now collides is left
    /// `pending` for a FIFO decision; unselected names are never enqueued.
    @discardableResult
    func commit(selectedIDs: Set<UUID>) -> ImportSummary {
        var result = ImportSummary()
        for candidate in candidates where selectedIDs.contains(candidate.id) {
            if let conflict = store.conflictingChecklist(named: candidate.checklist.name) {
                pending.append(ChecklistImportCandidate(
                    id: candidate.id, checklist: candidate.checklist, conflicting: conflict))
            } else {
                store.importInsert(candidate.checklist)
                result.inserted += 1
            }
        }
        summary = result
        return result
    }

    /// Drops a staged file (Cancel / swipe-away). No store writes either way.
    func discard() {
        candidates = []
        pending = []
        summary = ImportSummary()
    }

    /// The decode+migrate half of the old `prepare`.
    private func decoded(_ data: Data) throws -> [Checklist] {
        switch ChecklistCodec.classify(data) {
        case .loaded(let envelope):
            return envelope.checklists
        case .migratable(let from, let envelope):
            return envelope.checklists.map { checklist in
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