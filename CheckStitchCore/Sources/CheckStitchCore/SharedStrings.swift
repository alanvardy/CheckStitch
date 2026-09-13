import Foundation

/// Centralized, typed access to the Core package's user-facing strings. Every
/// value resolves through `Bundle.module` (the package's compiled
/// `Localizable.xcstrings`), never a caller's bundle.
public enum SharedStrings {
    public static var system: String {
        String(localized: "System", table: "Localizable", bundle: .module)
    }

    public static var light: String {
        String(localized: "Light", table: "Localizable", bundle: .module)
    }

    public static var dark: String {
        String(localized: "Dark", table: "Localizable", bundle: .module)
    }
}
