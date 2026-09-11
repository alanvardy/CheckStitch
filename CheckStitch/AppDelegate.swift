#if os(iOS)
    import UIKit

    /// Bridges the persisted appearance setting into the UIKit window so the
    /// theme applies app-wide rather than per-view.
    ///
    /// Registered via `@UIApplicationDelegateAdaptor` in `MyApp`.
    final class AppDelegate: NSObject, UIApplicationDelegate {
        /// Applies the persisted appearance to every window in every connected
        /// scene, and on demand to explicit windows. The `.system` sentinel
        /// (`.unspecified`) clears any prior override so the window re-follows
        /// the device — replaying Light → System converges reliably.
        static func applyAppearance(_ mode: AppearanceMode, to windows: [UIWindow]? = nil) {
            let targets = windows
                ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            for window in targets {
                window.overrideUserInterfaceStyle = mode.windowOverrideStyle
            }
        }

        func applicationDidBecomeActive(_: UIApplication) {
            Self.applyAppearance(AppearanceMode.load())
        }
    }
#endif
