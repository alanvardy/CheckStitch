import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

// MARK: - AppearanceMode

/// The app's appearance override, persisted in `UserDefaults` via `@AppStorage`.
/// Applied at the window level (`UIWindow.overrideUserInterfaceStyle` on iOS,
/// `NSWindow.appearance` on macOS). `.system` clears the override so the app
/// follows the device.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    // MARK: Public

    #if os(iOS)
        /// The window interface style to force, or the "clear override → follow
        /// device" sentinel for `.system`.
        public var windowOverrideStyle: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
        }
    #endif

    #if os(macOS)
        /// The `NSAppearance` to force, or `nil` for `.system` (clear override
        /// → follow the system).
        public var appKitAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    #endif

    /// The `ColorScheme` to force in SwiftUI content, or `nil` for `.system` to
    /// follow the device. On macOS the canvas does not pick up the window-level
    /// `NSWindow.appearance`, so `ContentView`/`SettingsView` thread this via
    /// `preferredColorScheme`; previews (no window to override) use it the same
    /// way instead of `windowOverrideStyle` / `appKitAppearance`.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// SF Symbol shown alongside the label in the appearance picker.
    public var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// Human-readable label shown in the appearance picker.
    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Reads the persisted appearance from `UserDefaults`, defaulting to
    /// `.system` for a missing or unknown value. Mirrors `@AppStorage`'s
    /// fallback-to-default.
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: AppearanceModePreference(defaults: defaults).rawValue) ?? .system
    }
}

// MARK: - AppearanceModePreference

/// Persists the appearance-mode raw string in `UserDefaults.standard`.
///
/// An absent or unrecognized key resolves to `"system"`.
public struct AppearanceModePreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Single shared key used by `@AppStorage` and `AppearanceMode.load(from:)`.
    public static let defaultsKey = "appearanceMode"

    /// Returns the raw value string (`"system"` | `"light"` | `"dark"`),
    /// falling back to `"system"` for missing/unrecognized keys.
    public var rawValue: String {
        guard let raw = defaults.object(forKey: key) as? String,
              ["system", "light", "dark"].contains(raw)
        else { return "system" }
        return raw
    }

    public func setRawValue(_ raw: String) {
        defaults.set(raw, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
