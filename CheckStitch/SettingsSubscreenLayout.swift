import SwiftUI

#if os(macOS)
    /// Frames content to fill the available height and top-align,
    /// fixing the macOS sheet's vertical-centering bug for pushed
    /// settings sub-views.
    private struct SettingsSubscreenLayout: ViewModifier {
        func body(content: Content) -> some View {
            content.frame(maxHeight: .infinity, alignment: .top)
        }
    }
#endif

extension View {
    /// Fills and top-aligns the receiving view on macOS; a no-op on iOS
    /// where `settingsSubscreenLayout()` returns the receiver unchanged
    /// so the iOS Settings surface is untouched.
    func settingsSubscreenLayout() -> some View {
        #if os(macOS)
            modifier(SettingsSubscreenLayout())
        #else
            self
        #endif
    }
}
