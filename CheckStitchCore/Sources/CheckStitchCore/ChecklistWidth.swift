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

    /// Cap for the pushed checklist edit forms (`ChecklistDetailView` and
    /// `ItemEditView`). A phone-width viewport is used whole, so the form fills
    /// the screen; a wide (iPad) viewport is capped at twice the list card's
    /// ceiling so the form keeps a centred reading column instead of stretching
    /// edge to edge.
    nonisolated public static func editFormMaxWidth(viewportWidth: CGFloat) -> CGFloat {
        min(680, viewportWidth)
    }
}
