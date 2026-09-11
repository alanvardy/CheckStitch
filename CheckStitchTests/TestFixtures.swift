import CheckStitchCore
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