import Foundation

/// User-selectable app language. `.system` preserves the device locale (today's
/// behaviour); the other cases pin the app to one of the six shipped catalogs.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"

    /// Locale for SwiftUI's `\.locale` and explicit lookups. `.system` follows
    /// the device; the six pinned cases map to their catalog language.
    public var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }

    /// Reads the persisted language, defaulting to `.system` for a missing or
    /// unknown value. Mirrors `AppearanceMode.load(from:)`.
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        AppLanguagePreference(defaults: defaults).load()
    }
}