import SwiftUI

/// Suppresses the platform-default button chrome so CheckStitch's buttons
/// render as their own drawn plates without macOS's lighter grey bezel or
/// iOS's toolbar chip (the translucent white oval iOS 26 paints behind icon
/// buttons in the navigation bar). In dark mode the default chrome's grey
/// background looks wrong against the app's dark appearance, so these
/// buttons use `.borderless`.
///
/// On macOS it removes the translucent bezel the default style draws around
/// a button's label; on iOS it removes the toolbar's circular chip. No `#if
/// os` inside so the shared (cross-platform) buttons call the same symbol.
struct CheckStitchButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderless)
    }
}

extension View {
    /// Applies `.buttonStyle(.borderless)` through one shared symbol so the
    /// chrome-suppression decision lives in a single place.
    func checkStitchButton() -> some View {
        modifier(CheckStitchButtonModifier())
    }
}
