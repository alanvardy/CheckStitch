import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

extension Color {
    /// Cross-platform system background color.
    ///
    /// Maps to `UIColor.systemBackground` on iOS and watchOS, and
    /// `NSColor.windowBackgroundColor` on macOS, so shared views can reference
    /// one symbol instead of guarding each platform inline.
    static var systemBackground: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }
}
