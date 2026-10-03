import Foundation

/// Persists the crash-reporting consent flag in `UserDefaults.standard`.
///
/// Device-local by design: the watch and widget must not acquire the crash
/// reporter, so this key is deliberately *not* in the App Group and is not
/// synced over WatchConnectivity. An absent key resolves to `true` (reporting
/// enabled by default).
public struct CrashReportingPreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by the settings toggle and `SentryBootstrap`.
    public static let defaultsKey = "crashReportingEnabled"

    /// Whether crash reporting is enabled. `nil` (missing key) → `true`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
