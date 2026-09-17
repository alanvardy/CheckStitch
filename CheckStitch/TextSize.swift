import SwiftUI

// MARK: - TextSize

/// User-selectable text size preference, persisted in `UserDefaults` via
/// `@AppStorage`. Follows the same `String, CaseIterable` pattern as
/// ``AppearanceMode`` so it slots into the Interface picker.
enum TextSize: String, CaseIterable {
    case system
    case small
    case medium
    case large
    case extraLarge

    // MARK: Internal

    /// The `DynamicTypeSize` to apply, or `nil` to follow the system.
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .small: .small
        case .medium: .medium
        case .large: .xLarge
        case .extraLarge: .xxxLarge
        }
    }

    /// SF Symbol shown alongside the label in the text-size picker.
    var systemImage: String {
        switch self {
        case .system: "textformat.size"
        case .small: "textformat.size.smaller"
        case .medium: "textformat.size"
        case .large: "textformat.size.larger"
        case .extraLarge: "textformat.size.larger"
        }
    }

    /// Human-readable label shown in the text-size picker.
    var title: String {
        switch self {
        case .system: String(localized: "System", table: "Localizable", bundle: .main)
        case .small: String(localized: "Small", table: "Localizable", bundle: .main)
        case .medium: String(localized: "Medium", table: "Localizable", bundle: .main)
        case .large: String(localized: "Large", table: "Localizable", bundle: .main)
        case .extraLarge: String(localized: "Extra Large", table: "Localizable", bundle: .main)
        }
    }
}
