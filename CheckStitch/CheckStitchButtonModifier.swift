import SwiftUI

/// Suppresses the platform-default button chrome so CheckStitch's buttons
/// render as their own drawn plates without macOS's lighter grey bezel. In
/// dark mode the default chrome's grey background looks wrong against the
/// app's dark appearance, so these buttons use `.borderless`.
///
/// iOS/iPadOS already render these buttons chrome-less, so `.borderless` is a
/// no-op there; on macOS it removes the translucent bezel the default style
/// draws around a button's label. Intentionally no `#if os` inside so the
/// shared (cross-platform) buttons can call the same symbol.
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