import Foundation
#if os(iOS)
    import UIKit
#endif

// MARK: - OrientationPreference

/// Persists the "allow landscape" preference in `UserDefaults.standard`.
///
/// This key is read at launch by `AppDelegate` before any SwiftUI view exists
/// (so the persisted lock takes effect without a wrong-orientation flash),
/// hence plain `UserDefaults` rather than the App Group suite. An absent key
/// resolves to `true` — landscape enabled, which is the Info.plist default.
struct OrientationPreference {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Internal

    /// Single shared key used by `AppDelegate`, `@AppStorage`, and settings.
    static let defaultsKey = "allowsLandscape"

    /// Whether landscape orientation is enabled. `nil` (missing key) → `true`.
    var isLandscapeEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    func setLandscapeEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}

// MARK: - OrientationPolicy

/// Which orientations the app allows, derived from ``OrientationPreference``.
///
/// Deliberately cross-platform so the selection logic is unit-testable on the
/// macOS-hosted suite; the UIKit mask lives in the iOS-only extension below.
enum OrientationPolicy: String, CaseIterable {
    case portrait
    case allButUpsideDown

    init(allowsLandscape: Bool) {
        self = allowsLandscape ? .allButUpsideDown : .portrait
    }
}

#if os(iOS)
    extension OrientationPolicy {
        var mask: UIInterfaceOrientationMask {
            switch self {
            case .portrait: .portrait
            case .allButUpsideDown: .allButUpsideDown
            }
        }
    }
#endif
