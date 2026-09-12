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

#if os(macOS)
    import AppKit

    /// macOS counterpart to `AppDelegate`: bridges the persisted appearance
    /// setting into every `NSWindow` so the theme applies app-wide rather than
    /// per-view, and keeps every window reachable on screen.
    ///
    /// Registered via `@NSApplicationDelegateAdaptor` in `MyApp`.
    final class MacAppDelegate: NSObject, NSApplicationDelegate {
        /// Re-applies `mode` to every open window. `.system` maps to `nil`,
        /// clearing the explicit appearance so windows follow the system —
        /// mirroring the iOS override-clear behavior.
        static func applyAppearance(_ mode: AppearanceMode) {
            for window in NSApp.windows {
                window.appearance = mode.appKitAppearance
            }
        }

        /// Moves an unreachable `windowFrame` back onto the first screen in
        /// `NSScreen.screens` (the "zero" screen), preserving its size when it fits
        /// and shrinking it when it does not. Only frames that intersect no screen at all are touched — a window
        /// that is even partly visible is left exactly where the user (or the last
        /// session) placed it. An empty screen list returns the window frame
        /// unchanged so a window is never displaced before the window server is
        /// reachable.
        nonisolated static func onScreenFrame(_ windowFrame: NSRect, screenFrames: [NSRect]) -> NSRect {
            guard let primary = screenFrames.first, !windowFrame.isEmpty else {
                return windowFrame
            }
            let isOffScreen = screenFrames.allSatisfy { $0.intersection(windowFrame).isEmpty }
            guard isOffScreen else {
                return windowFrame
            }
            // Centered on the primary screen, shrunk only to fit.
            let width = min(windowFrame.width, primary.width)
            let height = min(windowFrame.height, primary.height)
            return NSRect(
                x: primary.origin.x + (primary.width - width) / 2,
                y: primary.origin.y + (primary.height - height) / 2,
                width: width,
                height: height)
        }

        /// Re-frames windows whose persisted frame sits off any screen. SwiftUI's
        /// macOS scene restore blindly replays the last `NSWindow Frame` from the
        /// preferences, which — once off-screen — can never be clicked back; healing
        /// it here keeps the close button reachable no matter what was persisted.
        /// Idempotent: on-screen windows are left untouched.
        private func clampWindowsToScreen() {
            let screenFrames = NSScreen.screens.map(\.frame)
            for window in NSApp.windows {
                // Without any screen geometry (window server still settling at
                // launch) fall back to a conservative top-left placement rather
                // than leaving an off-screen window unreachable.
                let target = if screenFrames.isEmpty {
                    NSRect(x: 0, y: 0, width: min(window.frame.width, 1512), height: min(window.frame.height, 982))
                } else {
                    Self.onScreenFrame(window.frame, screenFrames: screenFrames)
                }
                if target != window.frame {
                    window.setFrame(target, display: false)
                }
            }
        }

        /// Re-clamps whenever any window is moved. SwiftUI's scene restore can
        /// reapply a persisted off-screen frame after the launch callbacks above
        /// have run, so a one-shot clamp at launch can race it; catching every
        /// move converges no matter when the restore lands. Harmless for user
        /// repositions: on-screen frames stay untouched.
        @objc private func windowDidMove(_: Notification) {
            clampWindowsToScreen()
        }

        /// Heals the persisted frame just before SwiftUI writes it back at window
        /// teardown. SwiftUI only persists each window's frame when it closes, so an
        /// off-screen frame that a launch restore replays keeps re-persisting
        /// itself; re-framing on the way out makes the next launch restore a
        /// reachable window instead.
        @objc private func windowWillClose(_: Notification) {
            clampWindowsToScreen()
        }

        func applicationDidFinishLaunching(_: Notification) {
            Self.applyAppearance(AppearanceMode.load())
            clampWindowsToScreen()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidMove(_:)),
                name: NSWindow.didMoveNotification,
                object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: nil)
        }

        func applicationDidBecomeActive(_: Notification) {
            Self.applyAppearance(AppearanceMode.load())
            clampWindowsToScreen()
        }

        /// Standard macOS lifecycle: closing the last window keeps the app active
        /// in the Dock (Cmd-Q still quits), and a Dock click / `open` re-hosts the
        /// scene window via the SwiftUI app shell.
        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
            false
        }

        func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
            true
        }
    }
#endif
