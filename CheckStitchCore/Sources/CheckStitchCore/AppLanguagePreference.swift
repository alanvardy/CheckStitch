import Foundation

/// Persists the app-language raw string in `UserDefaults.standard`. An absent or
/// unrecognized value resolves to `.system`, preserving today's behaviour.
public struct AppLanguagePreference {
    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public static let defaultsKey = "appLanguage"

    /// Validated raw value; missing/unrecognized → `AppLanguage.system.rawValue`.
    public var rawValue: String {
        guard let raw = defaults.object(forKey: key) as? String,
              AppLanguage.allCases.contains(where: { $0.rawValue == raw })
        else { return AppLanguage.system.rawValue }
        return raw
    }

    public func load() -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }

    public func setRawValue(_ raw: String) {
        defaults.set(raw, forKey: key)
    }

    private let defaults: UserDefaults
    private let key: String
}