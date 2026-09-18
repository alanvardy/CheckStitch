import Foundation
import Observation

/// Process-wide holder of the chosen language. One instance per process,
/// injected at the app and watch roots into `\.locale`; tests construct their
/// own with an isolated `UserDefaults` suite.
@MainActor
@Observable
public final class AppLocaleState {
    public init(language: AppLanguage? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = language ?? AppLanguagePreference(defaults: defaults).load()
    }

    /// Shared instance used by the app and watch roots and by the Settings picker.
    public static let current = AppLocaleState()

    /// Locale for non-View consumers (intents, `LocalizedError`s, `AppInfo`).
    /// A plain store read, no actor hop, so it never registers observation.
    public nonisolated static var storedEffectiveLocale: Locale {
        AppLanguagePreference().load().locale
    }

    public private(set) var language: AppLanguage

    /// Locale handed to SwiftUI's `\.locale` and to `resolved(in:)`.
    public var effectiveLocale: Locale { language.locale }

    /// Persists and publishes the choice. Later slices must never read
    /// `AppLanguagePreference` directly — only this holder.
    public func set(_ language: AppLanguage) {
        AppLanguagePreference(defaults: defaults).setRawValue(language.rawValue)
        self.language = language
    }

    private let defaults: UserDefaults
}