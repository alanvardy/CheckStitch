import CoreGraphics

/// Viewport-relative cap for the checklist content, mirroring SingleThread's
/// CardWidth. Returns `min(ceiling, fraction)` so the content hugs narrow
/// screens but never balloons on wide (iPad) screens.
///
/// `nonisolated` keeps the pure math callable outside the app target's
/// `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
public enum ChecklistWidth {
    nonisolated public static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat {
        min(340, viewportWidth * 0.6)
    }
}