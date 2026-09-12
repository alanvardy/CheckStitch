import CheckStitchCore
import EventKit
import Foundation

/// Builds an item without saving anything anywhere.
func makeItem(_ title: String) -> ChecklistItem {
    ChecklistItem(title: title)
}

/// A `UserDefaults` isolated from `.standard`, wiped so appearance suites can
/// never read or write the real app preference.
func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "CheckStitchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// A single `EKEventStore` kept alive for the test session. `EKReminder` holds
/// a weak reference to its store, so a deallocated store crashes (SIGTRAP) on
/// any property read — this global must outlive every reminder built from it.
@MainActor
let sharedTestEventStore = EKEventStore()

/// Test double for `ReminderCreating`: records created titles and can be told
/// to deny access or throw. `@MainActor` makes it implicitly `Sendable`.
@MainActor
final class SpyReminderCreator: ReminderCreating {
    var accessGranted = true
    var accessError: Error?
    var createError: Error?
    /// Invoked at the start of every `create(title:)` — lets a suite observe
    /// view-model state while the work is in flight.
    var onCreate: (() -> Void)?
    private(set) var createdTitles: [String] = []

    func requestAccess() async throws -> Bool {
        if let accessError { throw accessError }
        return accessGranted
    }

    func create(title: String) async throws {
        if let createError { throw createError }
        onCreate?()
        createdTitles.append(title)
    }
}

/// Deterministic error for failure-path assertions.
enum TestError: Error, Equatable {
    case boom
}
