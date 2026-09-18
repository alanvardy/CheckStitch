import Foundation

/// Centralized, typed access to the Core package's user-facing strings. Every
/// value resolves through `Bundle.module` (the package's compiled
/// `Localizable.xcstrings`), never a caller's bundle. A resource, so SwiftUI
/// re-resolves it against `\.locale` on a live language switch.
public enum SharedStrings {
    public static var system: LocalizedStringResource {
        LocalizedStringResource("System", table: "Localizable", bundle: .module)
    }

    public static var light: LocalizedStringResource {
        LocalizedStringResource("Light", table: "Localizable", bundle: .module)
    }

    public static var dark: LocalizedStringResource {
        LocalizedStringResource("Dark", table: "Localizable", bundle: .module)
    }
}
