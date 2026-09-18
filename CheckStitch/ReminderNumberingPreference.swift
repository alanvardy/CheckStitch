import Foundation

// MARK: - ReminderNumberingPreference

/// Persists the "number reminders" preference in `UserDefaults.standard`,
/// matching the other `@AppStorage`-backed preferences. Read outside SwiftUI by
/// the phone-sync coordinator and the Run Checklist intent.
struct ReminderNumberingPreference {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Internal

    /// Single shared key used by `@AppStorage` and the non-View read sites.
    static let defaultsKey = "prefixReminderNumbers"

    /// Whether created reminder titles get a 1-based prefix. Missing key → false.
    var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
